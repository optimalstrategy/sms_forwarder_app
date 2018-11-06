import 'dart:math';
import 'dart:core';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sms/sms.dart';
import 'package:flutter/foundation.dart';

/// Defines forwarder interface.
abstract class AbstractForwarder {
  /// Forwards sms to a user
  Future<bool> forward(SmsMessage sms);

  /// Unnamed constructor
  AbstractForwarder();

  /// Constructs forwarder from json
  AbstractForwarder.fromJson(Map json);

  /// Dumps class to json
  String toJson();
}

/// A simple forwarder for debugging.
class StdoutForwarder implements AbstractForwarder {
  /// Writes received sms to stdout
  Future<bool> forward(SmsMessage sms) async {
    print("Received an sms: ${sms.body}.");
    return Future<bool>(() => true);
  }

  /// Default constructor
  StdoutForwarder();

  /// Just to support the interface
  StdoutForwarder.fromJson(Map json);

  /// Dumps this class to json
  @override
  String toJson() => '{"StdoutForwarder": {}}';
}

/// HTTP forwarder. Provides implementation for the [forward] method and
/// [mapToUri], but requires user to implement [get].
abstract class HttpForwarder implements AbstractForwarder {
  /// Creates uri parameters string out of given [map].
  /// NOTE: value with key 'thread_id' will be removed.
  /// Example: `mapToUri({"msg":  "test message", "code": 10})` produces
  /// `?msg=test%20message&code=10&`
  static String mapToUri(Map map) {
    String uri = "?";
    var body = map
    // Remove `thread_id`,
      ..removeWhere((k, v) => k == 'thread_id')
      // Cast each field to string
      ..map((k, v) => MapEntry(k, v.toString()));
    // Encode and build uri parameters
    body.forEach((k, v) => uri += "$k=${Uri.encodeComponent(v.toString())}&");
    return uri;
  }

  /// Makes http request and returns request object.
  Future<http.Response> get(SmsMessage sms);

  /// Default implementation of [forward].
  /// Awaits request and returns true if statusCode is 200.
  @override
  Future<bool> forward(SmsMessage sms) async {
    return Future<bool>(() async {
      // Make GET request
      var response = await get(sms);
      // TODO: remove debug prints
      debugPrint("Response status: ${response.statusCode}.");
      debugPrint("Response body: \'${response.body}\'.");
      // Return true if status is 200
      return response.statusCode == 200;
    });
  }

}

/// Forwards SMS to provided [_callbackUrl].
class HttpCallbackForwarder extends AbstractForwarder with HttpForwarder {
  /// Messages will be sent to [_callbackUrl]
  String _callbackUrl;

  /// Getter for the callback
  String get callbackUrl => _callbackUrl;

  /// Frontend is responsible for checking the {proto}:// part.
  HttpCallbackForwarder(this._callbackUrl);

  /// Constructs HttpCallbackForwarder from [json]
  @override
  HttpCallbackForwarder.fromJson(Map json) {
    if (json.containsKey("HttpCallbackForwarder")) {
      json = json["HttpCallbackForwarder"];
    }
    _callbackUrl = json["callbackUrl"];
    // Check if all required fields are provided
    if (_callbackUrl == null) throw ArgumentError("Bad json");
  }

  /// Simply converts SMS to a uri,
  /// then makes a GET request to [_callbackUrl].
  @override
  Future<http.Response> get(SmsMessage sms) {
    String uriParams = HttpForwarder.mapToUri(sms.toMap);
    return http.get("$_callbackUrl$uriParams");
  }

  /// Dumps HttpCallbackForwarder to json
  @override
  String toJson() {
    var fields = json.encode({"callbackUrl": _callbackUrl});
    return '{"HttpCallbackForwarder": $fields}';
  }
}

/// Forwards SMS using provided Telegram bot [_token] and user's [_chatId].
class TelegramBotForwarder extends AbstractForwarder with HttpForwarder {
  /// Telegram bot token
  String _token;
  /// Telegram chat id
  int _chatId;
  /// Getter for the token
  String get token => _token;
  /// Getter for the chatId
  int get chatId => _chatId;

  TelegramBotForwarder(this._token, this._chatId);

  /// Constructs TelegramBotForwarder from [json]
  @override
  TelegramBotForwarder.fromJson(Map json) {
    if (json.containsKey("TelegramBotForwarder")) {
      json = json["TelegramBotForwarder"];
    }
    _token = json["token"];
    _chatId = json["chatId"];
    // Check if all required fields are provided
    if (_token == null || _chatId == null) throw ArgumentError("Bad json");
  }

  /// Constructs base Telegram Bot API url
  get api {
    return "https://api.telegram.org/bot$_token";
  }

  /// Constructs Telegram Bot API url using provided [methodName].
  String method(String methodName) {
    return "$api/$methodName";
  }

  /// Sends SMS data to [_chatId].
  @override
  Future<http.Response> get(SmsMessage sms) {
    // Encode message
    String uriParams = HttpForwarder.mapToUri({
      "chat_id": _chatId,
      "text": "New SMS message from ${sms.address}:\n${sms.body}\n\n"
              "Date: ${sms.date}."
    });
    // Send message to user using Telegram Bot API
    String url = this.method("sendMessage");
    return http.get("$url$uriParams");
  }

  /// Dumps TelegramBotForwarder to json
  @override
  String toJson() {
    var fields = {"token": _token, "chatId": _chatId};
    return json.encode({"TelegramBotForwarder": fields});
  }
}

/// Sends SMS data to a server
class DeployedTelegramBotForwarder extends HttpCallbackForwarder {
  String _tgCode;
  String _baseUrl;
  String _tgHandle;
  String _botHandle;
  bool _isSetUp = false;

  /// Getters
  bool get isSetUp => _isSetUp;
  String get baseUrl => _baseUrl;
  String get tgHandle => _tgHandle;
  String get botHandle => _botHandle;

  /// Default constructor
  DeployedTelegramBotForwarder(
      this._tgHandle, {
        baseUrl: "https://forwarder.whatever.team",
        botHandle: "smsforwarderrobot"
      }) : super("$baseUrl/forward") {
    _baseUrl = baseUrl;
    _botHandle = botHandle;
    _tgCode = _genCode();
  }

  /// Constructs DeployedTelegramBotForwarder from [json]
  DeployedTelegramBotForwarder.fromJson(Map json) : super(null) {
    if (json.containsKey("DeployedTelegramBotForwarder")) {
        json = json['DeployedTelegramBotForwarder'];
    }
    _baseUrl = json['baseUrl'] ?? "https://forward.whatever.team";
    _botHandle = json['botHandle'] ?? "smsforwarderrobot";
    _tgHandle = json['tgHandle'];
    _tgCode = json['tgCode'] ?? _genCode();
    super._callbackUrl = '$_baseUrl/forward';
    // Check if all required fields are provided
    if (_tgHandle == null) throw ArgumentError("Bad json");
  }

  /// Returns url that updates (or creates) code
  String getUrl() {
    return "https://t.me/$_botHandle?start=${_tgCode}_$_tgHandle";
  }

  /// Checks if user with [_tgHandle] exist on the server
  Future<bool> checkSetupURL() async {
    var params = {"username": _tgHandle, "code": _tgCode};
    var r = await http.get(
        "$_baseUrl/check_user${HttpForwarder.mapToUri(params)}"
    );
    _isSetUp = r?.statusCode == 200;
    return Future<bool>(() => isSetUp);
  }

  Future<http.Response> get(SmsMessage sms) {
    var map = sms.toMap;
    map['date'] = sms.date.toString(); // default date field is in millisecond
    String uriParams = HttpForwarder.mapToUri(map);
    String url = "$_callbackUrl${uriParams}code=$_tgCode&username=$_tgHandle";
    return http.get(url);
  }

  /// Generates random 8-character code
  String _genCode() {
    var rand = Random();
    return String.fromCharCodes(
      new List.generate(8, (_) => rand.nextInt(26) + 65)
    );
  }

  /// Dumps DeployedTelegramBotForwarder to json
  @override
  String toJson() {
    var fields = {
      "tgCode": _tgCode,
      "baseUrl": _baseUrl,
      "tgHandle": _tgHandle,
      "botHandle": _botHandle,
    };
    return json.encode({"DeployedTelegramBotForwarder": fields});
  }

}