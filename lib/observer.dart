import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms/sms.dart';
import 'forwarding.dart';

class ForwarderObserver {
  // Supported forwarders
  HttpCallbackForwarder httpCallbackForwarder;
  TelegramBotForwarder telegramBotForwarder;
  DeployedTelegramBotForwarder deployedTelegramBotForwarder;

  // Reflections in flutter? WHEN?
  /// Returns mapping (forwarder name -> forwarding result)
  Future<Map<String, bool>> forward(SmsMessage sms) async {
    Map<String, bool> map = {};
    map["HttpCallbackForwarder"] = await httpCallbackForwarder?.forward(sms);
    map["TelegramBotForwarder"] = await telegramBotForwarder?.forward(sms);
    map["DeployedTelegramBotForwarder"] =
      await deployedTelegramBotForwarder?.forward(sms);
    return map;
  }

  /// Returns mapping (forwarder name -> forwarder object)
  Map<String, AbstractForwarder> asMap() => {
    "HttpCallbackForwarder": httpCallbackForwarder,
    "TelegramBotForwarder": telegramBotForwarder,
    "DeployedTelegramBotForwarder": deployedTelegramBotForwarder,
  };

  /// Returns list of forwarder objects
  List<AbstractForwarder> asList() => asMap().values.toList();

  /// Returns mapping (forwarder name -> not null)
  Map<String, bool> reportReadiness()
  => asMap().map((k, v) => MapEntry(k, v != null));

  /// Loads forwarders from shared preferences
  Future<Map> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    String jsonString = prefs.getString("forwarders") ?? "{}";
    var map = json.decode(jsonString);
    httpCallbackForwarder = _tryLoad(() => HttpCallbackForwarder.fromJson(map));
    telegramBotForwarder = _tryLoad(() => TelegramBotForwarder.fromJson(map));
    deployedTelegramBotForwarder = _tryLoad(
            () => DeployedTelegramBotForwarder.fromJson(map));
    return Future(() => reportReadiness());
  }

  /// Attempts to load forwarder using provided closure [fromJson]
  T _tryLoad<T extends AbstractForwarder>(Function fromJson) {
    var instance;
    try {
      instance = fromJson();
    } catch (ArgumentError) {}
    return instance as T;
  }

  /// Dumps forwarders to shared preferences
  void dumpToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> serialized = [];
    for (var fwd in asList()) {
      if (fwd == null) continue;
      String json = fwd.toJson();
      // Remove trailing '{' and '}'
      serialized.add(json.substring(1, json.length - 1));
    }
    // Dump serialized forwarders to shared preferences
    var jsonStr = "{${serialized.join(', ')}}";
    prefs.setString("forwarders", jsonStr);
  }
}