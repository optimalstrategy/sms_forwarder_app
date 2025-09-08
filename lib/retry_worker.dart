import 'dart:async';

import 'package:another_telephony/telephony.dart' hide NetworkType;
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'retry_defs.dart';

import 'forwarding.dart';
import 'forwarding_queue.dart';
import 'manager.dart';

class RetryWorker {
  static Future<void> initialize() async {
    debugPrint('[RetryWorker] Initializing Workmanager');
    await Workmanager().initialize(_callbackDispatcher);
  }

  static Future<void> schedulePeriodic() async {
    debugPrint("[RetryWorker] Scheduling a periodic retry task");
    await Workmanager().registerPeriodicTask(
      'retry-forwarding-periodic',
      kRetryTask,
      constraints: Constraints(networkType: NetworkType.connected),
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  static Future<void> scheduleRetryOneOffImmediate() async {
    debugPrint("[RetryWorker] Scheduling a one-off retry task");
    await Workmanager().registerOneOffTask(
      'retry-forwarding-oneoff-${DateTime.now().millisecondsSinceEpoch}',
      kRetryTask,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 2),
    );
  }
}

@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('[RetryWorker] New task received $taskName');
    if (taskName != kRetryTask) return Future.value(true);
    try {
      // Recreate forwarder manager with stored configuration
      final mgr = ForwarderManager();
      await mgr.loadFromPrefs();
      debugPrint("[RetryWorker] ForwarderManager loaded.");

      final queue = ForwardingRequestQueue();

      // Process pending items sequentially. Limit per run to avoid ANRs.
      const int maxPerRun = kMaxItemsPerRun;
      int processed = 0;
      while (processed < maxPerRun) {
        final item = await queue.popPendingAndReserve();
        if (item == null) break;
        await _processItem(mgr, queue, item);
        processed += 1;
      }
      return Future.value(true);
    } catch (e, st) {
      debugPrint('Retry worker exception: $e\n$st');
      return Future.value(true);
    }
  });
}

Future<void> _processItem(ForwarderManager mgr, ForwardingRequestQueue queue,
    ForwardingQueueItem item) async {
  final sms = _reconstructSms(item.sms);

  // Track per-forwarder outcomes via updated map; compute summary at the end.

  // Clone forwarders map to mutate
  final updated = Map<String, ForwarderProgress>.from(item.forwarders);

  Future<void> attempt(String name, AbstractForwarder? fwd) async {
    final prog = updated[name];
    if (prog == null) return;

    // Skip if already success or non-retriable failure, or exceeded retries
    if (prog.state == ForwarderAttemptState.success ||
        prog.state == ForwarderAttemptState.nonRetriableFailure) {
      return;
    }
    if (prog.retryCount >= prog.maxRetries) {
      prog.state = ForwarderAttemptState.nonRetriableFailure;
      return;
    }
    if (fwd == null) {
      prog.state = ForwarderAttemptState.nonRetriableFailure;
      return;
    }

    try {
      if (fwd is HttpForwarder) {
        final r = await fwd.forwardWithResult(sms);
        if (r.success) {
          prog.state = ForwarderAttemptState.success;
        } else {
          final retryable = r.isNetworkError ||
              (r.statusCode != null && r.statusCode! >= 500);
          if (retryable) {
            prog.state = ForwarderAttemptState.retriableFailure;
            prog.retryCount += 1;
            prog.lastError = r.errorMessage;
          } else {
            prog.state = ForwarderAttemptState.nonRetriableFailure;
            prog.lastError = r.errorMessage;
          }
        }
      } else {
        final ok = await fwd.forward(sms);
        prog.state = ok
            ? ForwarderAttemptState.success
            : ForwarderAttemptState.nonRetriableFailure;
      }
    } catch (e) {
      // Treat as retriable network-ish error
      prog.state = ForwarderAttemptState.retriableFailure;
      prog.retryCount += 1;
      prog.lastError = e.toString();
    }
  }

  await attempt(kFwdHttp, mgr.httpCallbackForwarder);
  await attempt(kFwdTg, mgr.telegramBotForwarder);
  await attempt(kFwdDeployed, mgr.deployedTelegramBotForwarder);

  // Determine overall status
  final bool hasRetriable = updated.values
      .any((p) => p.state == ForwarderAttemptState.retriableFailure);
  if (hasRetriable) {
    item.status = QueueItemStatus.pending;
  } else if (updated.values
      .every((p) => p.state == ForwarderAttemptState.success)) {
    item.status = QueueItemStatus.success;
  } else if (updated.values
      .any((p) => p.state == ForwarderAttemptState.success)) {
    item.status = QueueItemStatus.partialFailure;
  } else {
    item.status = QueueItemStatus.failure;
  }

  item.forwarders = updated;
  if (hasRetriable) {
    item.retryCount += 1;
  }
  item.reservedAtMs = null; // release reservation
  item.lastAttemptAtMs = DateTime.now().millisecondsSinceEpoch;
  await queue.updateItem(item);
}

class _SmsMessagePdo implements SmsMessage {
  @override
  String? address;

  @override
  String? body;

  @override
  int? date;

  @override
  int? dateSent;

  @override
  int? id;

  @override
  bool? read;

  @override
  bool? seen;

  @override
  String? serviceCenterAddress;

  @override
  SmsStatus? status;

  @override
  String? subject;

  @override
  int? subscriptionId;

  @override
  int? threadId;

  @override
  SmsType? type;

  @override
  bool equals(SmsMessage other) {
    if (identical(this, other)) return true;
    try {
      return (id != null && other.id != null && id == other.id) ||
          (address == other.address &&
              body == other.body &&
              threadId == other.threadId &&
              date == other.date);
    } catch (_) {
      return false;
    }
  }
}

SmsMessage _reconstructSms(Map<String, dynamic> map) {
  final sms = _SmsMessagePdo();
  sms.address = map['address']?.toString();
  sms.body = map['body']?.toString();
  sms.id = (map['id'] is int)
      ? map['id'] as int?
      : int.tryParse(map['id']?.toString() ?? '');
  sms.date = (map['date'] is int)
      ? map['date'] as int?
      : int.tryParse(map['date']?.toString() ?? '');
  sms.dateSent = (map['dateSent'] is int)
      ? map['dateSent'] as int?
      : int.tryParse(map['dateSent']?.toString() ?? '');
  sms.read = (map['read'] is bool)
      ? map['read'] as bool?
      : (map['read']?.toString() == 'true');
  sms.seen = (map['seen'] is bool)
      ? map['seen'] as bool?
      : (map['seen']?.toString() == 'true');
  sms.subject = map['subject']?.toString();
  sms.subscriptionId = (map['subscriptionId'] is int)
      ? map['subscriptionId'] as int?
      : int.tryParse(map['subscriptionId']?.toString() ?? '');
  sms.threadId = (map['threadId'] is int)
      ? map['threadId'] as int?
      : int.tryParse(map['threadId']?.toString() ?? '');
  // status/type are optional and format may vary across OS versions; skip precise deserialization
  return sms;
}
