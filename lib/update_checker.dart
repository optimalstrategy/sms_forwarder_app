import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const String APP_VERSION = "v1.5.0";
const String GITHUB_URL = "https://github.com/optimalstrategy/"
    "sms_forwarder_app/releases/latest";
const String GITHUB_API_URL = "https://api.github.com/repos/"
    + "optimalstrategy/sms_forwarder_app/releases/latest";

Future<bool> isUpdateAvailable() async {
  try {
    var r = await http.get(GITHUB_API_URL);
    if (r.statusCode != 200) return false;
    var json = jsonDecode(r.body);
    return json["tag_name"] != APP_VERSION;
  } on HttpException {
    return false;
  } on JsonUnsupportedObjectError {
    return false;
  } on StateError {
    return false;
  }
}
