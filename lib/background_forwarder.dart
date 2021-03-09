import 'package:telephony/telephony.dart';

import 'forwarding.dart';
import 'manager.dart';

/// A wrapper for [ForwarderManager] that registers a background message handler.
/// Resets the background forwarder every time a field is updated.
class BackgroundForwarder {
  static ForwarderManager _backgroundManager;
  final ForwarderManager mgr = new ForwarderManager();

  BackgroundForwarder(Telephony telephony) {
    telephony.listenIncomingSms(
        onNewMessage: (msg) async => await mgr.forward(msg),
        onBackgroundMessage: onBackgroundMessage
    );
  }

  static void onBackgroundMessage(SmsMessage msg) async {
    if (_backgroundManager == null) {
      _backgroundManager = new ForwarderManager();
      await _backgroundManager.loadFromPrefs();
    }
    await _backgroundManager.forward(msg);
  }

  HttpCallbackForwarder get httpCallbackForwarder => mgr.httpCallbackForwarder;

  TelegramBotForwarder get telegramBotForwarder => mgr.telegramBotForwarder;

  DeployedTelegramBotForwarder get deployedTelegramBotForwarder =>
      mgr.deployedTelegramBotForwarder;

  set httpCallbackForwarder(HttpCallbackForwarder fwd) {
    mgr.httpCallbackForwarder = fwd;
    invalidateBackgroundManager();
  }

  set telegramBotForwarder(TelegramBotForwarder fwd) {
    mgr.telegramBotForwarder = fwd;
    invalidateBackgroundManager();
  }

  set deployedTelegramBotForwarder(DeployedTelegramBotForwarder fwd) {
    mgr.deployedTelegramBotForwarder = fwd;
    invalidateBackgroundManager();
  }

  /// Loads the forwarders from a json.
  Future<Map> loadFromPrefs() async {
    var result = await mgr.loadFromPrefs();
    return result;
  }

  /// Dumps the forwarders to shared preferences.
  void dumpToPrefs() async => mgr.dumpToPrefs();

  /// Returns the mapping (forwarder name -> not null)
  Map reportReadiness() {
    return mgr.reportReadiness();
  }

  /// Sets the background manager to `null`.
  static void invalidateBackgroundManager() {
    _backgroundManager = null;
  }
}
