import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'forwarding.dart';

import 'dart:core';

import 'package:flutter/foundation.dart';

class ForwarderManager {
  // Supported forwarders
  HttpCallbackForwarder httpCallbackForwarder;
  TelegramBotForwarder telegramBotForwarder;
  DeployedTelegramBotForwarder deployedTelegramBotForwarder;

  /// Returns the mapping (forwarder name -> forwarding result)
  Future<Map<String, bool>> forward(SmsMessage sms) async {
    Map<String, bool> map = {};
    map["HttpCallbackForwarder"] = await tryForward(httpCallbackForwarder, sms);
    map["TelegramBotForwarder"] = await tryForward(telegramBotForwarder, sms);
    map["DeployedTelegramBotForwarder"] =
        await tryForward(deployedTelegramBotForwarder, sms);
    debugPrint(map.toString());
    return map;
  }

  Future<bool> tryForward(AbstractForwarder fwd, SmsMessage sms) async {
    try {
      return await fwd?.forward(sms);
    } catch (ex) {
      debugPrint("Failed to forward the message with " +
          fwd.runtimeType.toString() +
          ": " +
          ex.toString());
      return false;
    }
  }

  /// Returns the mapping (forwarder name -> forwarder object)
  Map<String, AbstractForwarder> asMap() => {
        "HttpCallbackForwarder": httpCallbackForwarder,
        "TelegramBotForwarder": telegramBotForwarder,
        "DeployedTelegramBotForwarder": deployedTelegramBotForwarder,
      };

  /// Returns a list of forwarder objects.
  List<AbstractForwarder> asList() => asMap().values.toList();

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
  T _tryLoad<T extends AbstractForwarder>(Function fromJson) {
    var instance;
    try {
      instance = fromJson();
    } catch (ArgumentError) {}
    return instance as T;
  }

  /// Dumps the forwarders to shared preferences.
  void dumpToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    var jsonStr = dumpToJson();
    prefs.setString("forwarders", jsonStr);
  }
}
