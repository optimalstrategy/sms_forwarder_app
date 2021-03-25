import 'dart:math';
import 'dart:core';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:telephony/telephony.dart';
import 'package:flutter/foundation.dart';

extension ToMap on SmsMessage {
  Map get toMap {
    return {
      "id": this.id,
      "address": this.address,
      "body": this.body,
      "date": this.date,
      "dateSent": this.dateSent,
      "read": this.read,
      "seen": this.seen,
      "subject": this.subject,
      "subscriptionId": this.subscriptionId,
      "threadId": this.threadId,
      "type": this.type,
      "status": this.status,
    };
  }
}

/// Defines the forwarder interface.
abstract class AbstractForwarder {
  /// Should forward the given sms.
  Future<bool> forward(SmsMessage sms);

  /// A default constructor.
  AbstractForwarder();

  /// Should construct the forwarder from json.
  AbstractForwarder.fromJson(Map json);

  /// Should dump the forwarder's configuration to json.
  String toJson();
}

/// A simple forwarder for debugging.
class StdoutForwarder implements AbstractForwarder {
  /// Writes the received sms messages to stdout.
  Future<bool> forward(SmsMessage sms) async {
    print("Received an sms: ${sms.body}.");
    return Future<bool>(() => true);
  }

  /// A default constructor.
  StdoutForwarder();

  /// Does nothing.
  StdoutForwarder.fromJson(Map json);

  /// Dumps this class to json.
  @override
  String toJson() => '{"StdoutForwarder": {}}';
}

/// The abstract HTTP forwarder. Provides a default implementation of the
/// [forward] and [mapToUri] methods. Requires the user to implement [send].
abstract class HttpForwarder implements AbstractForwarder {
  /// Creates a uri encoded query string from the given [map].
  /// NOTE: the entry with the key 'thread_id' will be removed.
  /// Example: `mapToUri({"msg":  "test message", "code": 10})` produces
  /// `?msg=test%20message&code=10&`
  static String mapToUri(Map map) {
    String uri = "?";
    var body = _castMap(map);
    // Encode and build the uri parameters
    body.forEach((k, v) => uri += "$k=${Uri.encodeComponent(v.toString())}&");
    return uri;
  }

  /// Casts all keys and values in the map to String and serializes
  /// the resulting map as JSON.
  static String mapToJson(Map map) => json.encode(_castMap(map));

  /// Casts all keys and values in the map to String. Removes the entry with
  /// the key threadId.
  static Map<String, String> _castMap(Map map) {
    map.remove('threadId');
    return Map.from(map.map(
        // Cast each field to string
        (k, v) => MapEntry(k.toString(), v.toString())));
  }

  /// Should make an http request and return the request object.
  Future<http.Response> send(SmsMessage sms);

  /// Default implementation of [forward].
  /// Awaits the [send] request and returns `true` if the status code is 200.
  @override
  Future<bool> forward(SmsMessage sms) async {
    return Future<bool>(() async {
      var response = await send(sms);
      // TODO: remove debug prints
      debugPrint("Response status: ${response.statusCode}.");
      debugPrint("Response body: \'${response.body}\'.");
      return response.statusCode >= 200 && response.statusCode < 400;
    });
  }
}

/// The http methods that [HttpCallbackForwarder] may use.
enum HttpMethod { GET, POST, PUT }

extension HttpMethodExtension on HttpMethod {
  /// Returns the name of the corresponding HTTP method.
  // ignore: missing_return
  String get name {
    switch (this) {
      case HttpMethod.GET:
        return 'GET';
      case HttpMethod.POST:
        return 'POST';
      case HttpMethod.PUT:
        return 'PUT';
    }
  }
}

/// Forwards SMS messages to the provided [_callbackUrl].
class HttpCallbackForwarder extends AbstractForwarder with HttpForwarder {
  /// The url to forward the SMS messages to.
  String _callbackUrl;

  /// The http method that the forwarder will use when forwarding sms messages
  /// to [_callbackUrl]
  HttpMethod method = HttpMethod.POST;

  /// The optional URI payload.
  Map<String, String> uriPayload = {};

  /// The optional JSON payload (only used when performing PUT and POST requests).
  Map<String, String> jsonPayload = {};

  /// Returns the url of the callback.
  String get callbackUrl => _callbackUrl;

  /// Initializes the forwarder.
  /// The caller is responsible to make sure that the protocol is valid.
  HttpCallbackForwarder(this._callbackUrl,
      {this.method, this.uriPayload, this.jsonPayload});

  /// Creates a new HttpCallbackForwarder from the given [json] object.
  @override
  HttpCallbackForwarder.fromJson(Map json) {
    if (json.containsKey("HttpCallbackForwarder")) {
      json = json["HttpCallbackForwarder"];
    }
    _callbackUrl = json["callbackUrl"];
    if (_callbackUrl == null) throw ArgumentError("Missing the callback url.");

    var jsonMethod = json["method"] ?? "";
    switch (jsonMethod) {
      // The json is from a previous version of the application, default to GET.
      case "":
      case "GET":
        method = HttpMethod.GET;
        break;
      case "POST":
        method = HttpMethod.POST;
        break;
      case "PUT":
        method = HttpMethod.PUT;
        break;
      default:
        throw ArgumentError("Invalid HTTP method: `$jsonMethod`");
    }

    uriPayload = Map.from(json["uriPayload"] ?? {});
    jsonPayload = Map.from(json["jsonPayload"] ?? {});
  }

  /// Dumps the forwarder's configuration to json
  @override
  String toJson() {
    var fields = json.encode({
      "callbackUrl": _callbackUrl,
      "method": method.name,
      "uriPayload": uriPayload,
      "jsonPayload": jsonPayload
    });
    return '{"HttpCallbackForwarder": $fields}';
  }

  /// URI encodes the SMS' contents and appends the result to the callback url,
  /// then makes a [method] request to [_callbackUrl].
  @override
  // ignore: missing_return
  Future<http.Response> send(SmsMessage sms) {
    switch (method) {
      case HttpMethod.GET:
        // Convert the sms to JSON and merge it with the uri payload
        final smsData = sms.toMap;
        smsData.addAll(uriPayload);
        // Then URI encode the map and perform the request
        final uriParams = HttpForwarder.mapToUri(smsData);
        return http.get("$_callbackUrl$uriParams");

      case HttpMethod.POST:
      case HttpMethod.PUT:
        // Convert the sms to json and merge it with the json payload
        final payload = sms.toMap;
        payload.addAll(jsonPayload);
        // URI encode the uri payload and append it to the url
        final uriParams = HttpForwarder.mapToUri(uriPayload);
        final url = "$_callbackUrl$uriParams";
        // Perform the request using the required method
        return method == HttpMethod.POST
            ? http.post(url, body: HttpForwarder.mapToJson(payload))
            : http.put(url, body: HttpForwarder.mapToJson(payload));
    }
  }
}

/// Forwards SMS using the provided Telegram bot [_token] and [_chatId].
class TelegramBotForwarder extends AbstractForwarder with HttpForwarder {
  /// Telegram bot token.
  String _token;

  /// Telegram chat id.
  int _chatId;

  /// Telegram bot token.
  String get token => _token;

  /// Telegram chat id.
  int get chatId => _chatId;

  /// Creates a new TelegramBotForwarder instance.
  TelegramBotForwarder(this._token, this._chatId);

  /// Creates a new TelegramBotForwarder instances from [json].
  @override
  TelegramBotForwarder.fromJson(Map json) {
    if (json.containsKey("TelegramBotForwarder")) {
      json = json["TelegramBotForwarder"];
    }
    _token = json["token"];
    _chatId = json["chatId"];
    if (_token == null || _chatId == null)
      throw ArgumentError("Missing the token or chat id");
  }

  /// Constructs the base Telegram Bot API url.
  get api {
    return "https://api.telegram.org/bot$_token";
  }

  /// Constructs a Telegram Bot API url using the provided [methodName].
  String method(String methodName) {
    return "$api/$methodName";
  }

  /// Sends the SMS data to the user with [_chatId].
  @override
  Future<http.Response> send(SmsMessage sms) {
    final date = DateTime.fromMillisecondsSinceEpoch(sms.date);
    // Encode message
    String uriParams = HttpForwarder.mapToUri({
      "chat_id": _chatId,
      "text": "New SMS message from ${sms.address}:\n${sms.body}\n\n"
          "Date: $date."
    });
    final url = this.method("sendMessage");
    return http.post("$url$uriParams");
  }

  /// Dumps the forwarder's configuration to to json
  @override
  String toJson() {
    var fields = {"token": _token, "chatId": _chatId};
    return json.encode({"TelegramBotForwarder": fields});
  }
}

/// Forwards SMS messages to a deployed sms_forwarder_bot.
class DeployedTelegramBotForwarder extends HttpCallbackForwarder {
  String _tgCode;
  String _baseUrl;
  String _tgHandle;
  String _botHandle;
  bool _isSetUp = false;

  // Getters
  bool get isSetUp => _isSetUp;

  String get baseUrl => _baseUrl;

  String get tgHandle => _tgHandle;

  String get botHandle => _botHandle;

  /// Default constructor
  DeployedTelegramBotForwarder(this._tgHandle,
      {baseUrl: "https://forwarder.whatever.team",
      botHandle: "smsforwarderrobot"})
      : super("$baseUrl/forward") {
    _baseUrl = baseUrl;
    _botHandle = botHandle;
    _tgCode = _genCode();
  }

  /// Constructs a new DeployedTelegramBotForwarder instance from [json].
  DeployedTelegramBotForwarder.fromJson(Map json) : super(null) {
    if (json.containsKey("DeployedTelegramBotForwarder")) {
      json = json['DeployedTelegramBotForwarder'];
    }
    _baseUrl = json['baseUrl'] ?? "https://forward.whatever.team";
    _botHandle = json['botHandle'] ?? "smsforwarderrobot";
    _tgHandle = json['tgHandle'];
    _tgCode = json['tgCode'] ?? _genCode();
    super._callbackUrl = '$_baseUrl/forward';
    if (_tgHandle == null) throw ArgumentError("Missing the telegram handle");
  }

  /// Returns a url that updates (or creates) the confirmation code.
  String getUrl() {
    return "https://t.me/$_botHandle?start=${_tgCode}_$_tgHandle";
  }

  /// Checks if the user with [_tgHandle] exists on the server.
  Future<bool> checkSetupURL() async {
    final params = {"username": _tgHandle, "code": _tgCode};
    final r =
        await http.get("$_baseUrl/check_user${HttpForwarder.mapToUri(params)}");
    _isSetUp = r?.statusCode == 200;
    return Future<bool>(() => isSetUp);
  }

  /// Sends the SMS data to the server via a POST request.
  Future<http.Response> send(SmsMessage sms) {
    final map = sms.toMap;
    final date = DateTime.fromMillisecondsSinceEpoch(sms.date);
    map['date'] = date.toString();
    String payload = HttpForwarder.mapToJson(map);
    String url = "$_callbackUrl?code=$_tgCode&username=$_tgHandle";
    return http.post(url, body: payload);
  }

  /// Generates a random 8-character code.
  String _genCode() {
    final rand = Random();
    return String.fromCharCodes(
        new List.generate(8, (_) => rand.nextInt(26) + 65));
  }

  /// Dumps the forwarder's settings to json.
  @override
  String toJson() {
    final fields = {
      "tgCode": _tgCode,
      "baseUrl": _baseUrl,
      "tgHandle": _tgHandle,
      "botHandle": _botHandle,
    };
    return json.encode({"DeployedTelegramBotForwarder": fields});
  }
}
