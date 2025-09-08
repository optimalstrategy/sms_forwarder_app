import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:another_telephony/telephony.dart';
import 'package:sms_forwarder/retry_worker.dart';
import 'forwarding.dart';
import 'forwarding_queue.dart';
import 'retry_defs.dart';
import 'package:crypto/crypto.dart';

import 'dart:core';

import 'package:flutter/foundation.dart';

class ForwarderManager {
  // Supported forwarders
  HttpCallbackForwarder? httpCallbackForwarder;
  TelegramBotForwarder? telegramBotForwarder;
  DeployedTelegramBotForwarder? deployedTelegramBotForwarder;

  /// Returns the mapping (forwarder name -> forwarding result)
  Future<Map<String, bool?>> forward(SmsMessage sms) async {
    final Map<String, bool?> results = {};
    final Map<String, ForwarderProgress> progress = {};

    // Helper to classify a single forward attempt
    Future<void> handleForward(String name, AbstractForwarder? fwd) async {
      debugPrint(
          'Trying $name $fwd (isHttp ${fwd != null && fwd is HttpForwarder})');
      if (fwd == null) {
        results[name] = false;
        return;
      }

      try {
        if (fwd is HttpForwarder) {
          var r = await fwd.forwardWithResult(sms);
          debugPrint('SMS forwarded: $r');
          if (Random.secure().nextBool()) {
            r = ForwardAttemptResult(
                success: false, statusCode: 500, isNetworkError: true);
            debugPrint('Made result failed $r');
          }
          results[name] = r.success;
          if (r.success) {
            progress[name] = ForwarderProgress(
                forwarderName: name,
                state: ForwarderAttemptState.success,
                retryCount: 0,
                maxRetries: kDefaultMaxRetries);
          } else {
            final retriable = r.isNetworkError ||
                (r.statusCode != null && r.statusCode! >= 500);
            progress[name] = ForwarderProgress(
              forwarderName: name,
              state: retriable
                  ? ForwarderAttemptState.retriableFailure
                  : ForwarderAttemptState.nonRetriableFailure,
              retryCount: 0,
              maxRetries: kDefaultMaxRetries,
              lastError: r.errorMessage,
            );
          }
        } else {
          final ok = await fwd.forward(sms);
          results[name] = ok;
          progress[name] = ForwarderProgress(
            forwarderName: name,
            state: ok
                ? ForwarderAttemptState.success
                : ForwarderAttemptState.nonRetriableFailure,
            retryCount: 0,
            maxRetries: kDefaultMaxRetries,
            lastError: ok ? null : 'forward_failed',
          );
        }
      } catch (ex) {
        debugPrint("Failed to forward the message with " +
            fwd.runtimeType.toString() +
            ": " +
            ex.toString());
        results[name] = false;
        progress[name] = ForwarderProgress(
          forwarderName: name,
          state: ForwarderAttemptState.retriableFailure,
          retryCount: 0,
          maxRetries: kDefaultMaxRetries,
          lastError: ex.toString(),
        );
      }
    }

    await handleForward(kFwdHttp, httpCallbackForwarder);
    await handleForward(kFwdTg, telegramBotForwarder);
    await handleForward(kFwdDeployed, deployedTelegramBotForwarder);
    new StdoutForwarder().forward(sms);

    // If any retriable failures, queue the whole SMS for later retry
    final hasRetriable = progress.values
        .any((p) => p.state == ForwarderAttemptState.retriableFailure);
    if (hasRetriable) {
      final smsMap = sms.toMap;
      final key = _computeSmsKey(smsMap);
      final now = DateTime.now().millisecondsSinceEpoch;
      final item = ForwardingQueueItem(
        smsKey: key,
        sms: Map.from(smsMap.map((k, v) => MapEntry(k.toString(), v))),
        forwarders: progress,
        status: QueueItemStatus.pending,
        createdAtMs: now,
        updatedAtMs: now,
        retryCount: 0,
      );
      await ForwardingRequestQueue().putOrUpdate(item);
      await RetryWorker.scheduleRetryOneOffImmediate();
    }

    return results;
  }

  Future<bool> tryForward(AbstractForwarder? fwd, SmsMessage sms) async {
    try {
      return await fwd?.forward(sms) ?? false;
    } catch (ex) {
      debugPrint("Failed to forward the message with " +
          fwd.runtimeType.toString() +
          ": " +
          ex.toString());
      return false;
    }
  }

  /// Returns the mapping (forwarder name -> forwarder object)
  Map<String, AbstractForwarder?> asMap() => {
        kFwdHttp: httpCallbackForwarder,
        kFwdTg: telegramBotForwarder,
        kFwdDeployed: deployedTelegramBotForwarder,
      };

  /// Returns a list of forwarder objects.
  List<AbstractForwarder?> asList() => asMap().values.toList();

  /// Returns the mapping (forwarder name -> not null)
  Map<String, bool> reportReadiness() =>
      asMap().map((k, v) => MapEntry(k, v != null));

  /// Loads the forwarders from shared preferences.
  Future<Map> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    String jsonString = prefs.getString("forwarders") ?? "{}";
    loadFromJson(jsonString);
    return Future(() => reportReadiness());
  }

  /// Loads the forwarders from a json.
  Map loadFromJson(String jsonString) {
    var map = json.decode(jsonString);
    httpCallbackForwarder = _tryLoad(() => HttpCallbackForwarder.fromJson(map));
    telegramBotForwarder = _tryLoad(() => TelegramBotForwarder.fromJson(map));
    deployedTelegramBotForwarder =
        _tryLoad(() => DeployedTelegramBotForwarder.fromJson(map));
    return reportReadiness();
  }

  /// Dumps the forwarder settings to json.
  String dumpToJson() {
    List<String> serialized = [];
    for (var fwd in asList()) {
      if (fwd == null) continue;
      String json = fwd.toJson();
      // Remove the trailing '{' and '}'
      serialized.add(json.substring(1, json.length - 1));
    }
    return "{${serialized.join(', ')}}";
  }

  /// Attempts to load a forwarder of type [T] using the provided closure [fromJson].
  T? _tryLoad<T extends AbstractForwarder>(Function fromJson) {
    var instance = null;
    try {
      instance = fromJson();
    } catch (ArgumentError) {}
    return instance;
  }

  /// Dumps the forwarders to shared preferences.
  void dumpToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    var jsonStr = dumpToJson();
    prefs.setString("forwarders", jsonStr);
  }

  String _computeSmsKey(Map smsMap) {
    final id = smsMap['id']?.toString() ?? '';
    final address = smsMap['address']?.toString() ?? '';
    final date = smsMap['date']?.toString() ?? '';
    final threadId = smsMap['threadId']?.toString() ?? '';
    final body = smsMap['body']?.toString() ?? '';
    final payload = '$id|$threadId|$address|$date|$body';
    return sha256.convert(utf8.encode(payload)).toString();
  }
}
