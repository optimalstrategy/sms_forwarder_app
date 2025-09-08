import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_forwarder/update_checker.dart';
import 'package:another_telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';
import 'forwarding.dart';
import 'key_value_settings.dart';
import 'background_forwarder.dart';
import 'responsive.dart';

final NAVIGATOR_KEY = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(new MyApp(new BackgroundForwarder(Telephony.instance)));
}

class MyApp extends StatelessWidget {
  final BackgroundForwarder fwd;

  MyApp(this.fwd);

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: 'SMS Forwarder',
      theme: new ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.white54,
      ),
      home: new HomePage(title: 'SMS Forwarder ($APP_VERSION)', fwd: this.fwd),
      navigatorKey: NAVIGATOR_KEY,
    );
  }
}

class HomePage extends StatefulWidget {
  HomePage({Key? key, required this.title, required this.fwd})
      : super(key: key);

  final String title;
  final BackgroundForwarder fwd;

  @override
  _HomePageState createState() => new _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static final Color _greenColor = Colors.green.shade500;
  static final Color _yellowColor = Colors.yellow.shade500;

  Color _deployedBotBtnState = _yellowColor;
  Color _tgBotBtnState = _yellowColor;
  Color _callbackBtnState = _yellowColor;

  bool? _isUpdateAvailable;
  PermissionStatus? _permissionStatus;
  bool _showingPermissionDialog = false;
  Future<Null>? _isChecking = null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionStatus();
    _loadForwarders(); // Load the saved forwarding settings
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Loads forwarders' settings and updates the buttons.
  void _loadForwarders() async {
    var map = await widget.fwd.loadFromPrefs();
    setState(() => _setForwardersColors(map));
  }

  void _setForwardersColors(Map map) {
    setState(() {
      _deployedBotBtnState =
          map['DeployedTelegramBotForwarder'] ? _greenColor : _yellowColor;
      _tgBotBtnState = map['TelegramBotForwarder'] ? _greenColor : _yellowColor;
      _callbackBtnState =
          map['HttpCallbackForwarder'] ? _greenColor : _yellowColor;
    });
  }

  ButtonStyle _forwarderButtonStyle(Color color) {
    return TextButton.styleFrom(
        foregroundColor: Colors.black,
        backgroundColor: color,
        padding: EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(1))));
  }

  TextButton _getUpdateButton() {
    IconData icon;
    String label;

    if (_isUpdateAvailable == null) {
      icon = Icons.autorenew;
      label = "Checking for updates...";
      isUpdateAvailable().then((b) {
        setState(() => _isUpdateAvailable = b);
      });
    } else if (_isUpdateAvailable!) {
      icon = Icons.update_sharp;
      label = "An update is available";
    } else {
      icon = Icons.check;
      label = "App is up to date";
    }

    final url = Uri.parse(GITHUB_URL);
    return TextButton.icon(
      onPressed: () async => await launchUrl(url),
      icon: Icon(icon, color: Colors.white),
      label: Text(
        label,
        style: TextStyle(fontSize: 12, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
          backgroundColor: Colors.green,
          title: new Text(widget.title, style: TextStyle(fontSize: 16)),
          actions: <Widget>[_getUpdateButton()]),
      body: ResponsiveScaffoldBody(
        centerVertically: true,
        child: new Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Deployed bot forwarder button
            SizedBox(
              width: double.infinity,
              child: new TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            ForwarderScreen<DeployedTelegramBotForwarder>(
                                fwd: widget.fwd))).then(
                    (_) => _setForwardersColors(widget.fwd.reportReadiness())),
                style: _forwarderButtonStyle(_deployedBotBtnState),
                child: Text(
                  "Deployed Telegram Bot Forwarder",
                  style: new TextStyle(fontSize: 20),
                ),
              ),
            ),
            SizedBox(height: 8),
            // Telegram bot forwarder button
            SizedBox(
              width: double.infinity,
              child: new TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            ForwarderScreen<TelegramBotForwarder>(
                                fwd: widget.fwd))).then(
                    (_) => _setForwardersColors(widget.fwd.reportReadiness())),
                style: _forwarderButtonStyle(_tgBotBtnState),
                child: Text(
                  "Your Telegram Bot Forwarder",
                  style: new TextStyle(fontSize: 20),
                ),
              ),
            ),
            SizedBox(height: 8),
            // Http callback forwarder button
            SizedBox(
              width: double.infinity,
              child: new TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            ForwarderScreen<HttpCallbackForwarder>(
                                fwd: widget.fwd))).then(
                    (_) => _setForwardersColors(widget.fwd.reportReadiness())),
                style: _forwarderButtonStyle(_callbackBtnState),
                child: Text(
                  "HTTP Callback Forwarder",
                  style: new TextStyle(fontSize: 20),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog(
            context: context,
            builder: (_) => AppSettingsScreen(this.widget.fwd)),
        tooltip: "App Settings",
        child: Icon(Icons.settings),
      ),
    );
  }

  Future<void> _checkPermissionStatus() async {
    if (_isChecking != null) {
      await _isChecking;
      _isChecking = null;
      return await _checkPermissionStatus();
    }

    final completer = new Completer<Null>();
    _isChecking = completer.future;

    try {
      final status = await Permission.sms.status;
      final isPermanentlyDenied = await Permission.sms.isPermanentlyDenied;
      final isRestricted = await Permission.sms.isRestricted;
      _updateStatus(status);

      if (status != PermissionStatus.granted) {
        if (isPermanentlyDenied || isRestricted) {
          _showPermissionDialog();
        } else {
          await Permission.sms.request().then((statusResponse) async {
            if (statusResponse != PermissionStatus.granted) {
              openAppSettings();
            } else {
              _updateStatus(status);
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Caught an error while checking permissions ${e}");
    } finally {
      completer.complete();
      _isChecking = null;
    }
  }

  void _updateStatus(PermissionStatus status) {
    if (status != _permissionStatus) {
      setState(() {
        _permissionStatus = status;
      });
    }

    if (status == PermissionStatus.granted &&
        NAVIGATOR_KEY.currentContext != null) {
      if (NAVIGATOR_KEY.currentWidget is AlertDialog) {
        Navigator.of(NAVIGATOR_KEY.currentContext!).maybePop();
      }
    }
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionStatus();
    }
  }

  Future<void> _showPermissionDialog() async {
    if (NAVIGATOR_KEY.currentContext == null || _showingPermissionDialog) {
      return;
    }
    _showingPermissionDialog = true;

    try {
      await showDialog(
          context: NAVIGATOR_KEY.currentContext!,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('SMS Permissions Denied'),
              content: const Text(
                'This app requires access to SMS messages in order to forward them. '
                'Please grant the permission the Android settings.\n\n'
                'On more recent versions of Android, you may need to '
                '"Allow restricted permissions" in the top-right corner '
                'of the app settings before granting the SMS permission.',
              ),
              actions: <Widget>[
                TextButton(
                  style: TextButton.styleFrom(
                    textStyle: Theme.of(context).textTheme.labelLarge,
                  ),
                  child: const Text('Open Settings'),
                  onPressed: () {
                    Navigator.pop(context);
                    openAppSettings();
                  },
                ),
              ],
            );
          });
    } finally {
      _showingPermissionDialog = false;
    }
  }
}

class ForwarderScreen<T extends AbstractForwarder> extends StatefulWidget {
  const ForwarderScreen({Key? key, required this.fwd}) : super(key: key);

  final BackgroundForwarder fwd;

  /// Returns the state for the provided forwarder.
  static _ForwarderScreenState
      _selectStateClass<T extends AbstractForwarder>() {
    if (T == HttpCallbackForwarder) {
      return _HttpCallbackForwarderState();
    } else if (T == TelegramBotForwarder) {
      return _TelegramBotForwarderScreen();
    } else if (T == DeployedTelegramBotForwarder) {
      return _DeployedTelegramBotForwarderScreen();
    }
    throw ArgumentError("Invalid type $T.");
  }

  @override
  State<StatefulWidget> createState() => _selectStateClass<T>();
}

abstract class _ForwarderScreenState<T extends AbstractForwarder>
    extends State<ForwarderScreen<T>> {
  /// Checks if the given string is a valid url.
  bool _checkValidUrl(String s) {
    var re = RegExp(
      r"https?:\/\/(((www\.)?[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}"
      r"\b([-a-zA-Z0-9@:%_\+.~#?&//=]*))|([0-9aA-zZ.]+:[0-9]+))",
      caseSensitive: false,
    );
    return re.hasMatch(s);
  }

  /// Common style for auxiliary action buttons across forwarder screens.
  ButtonStyle get _auxButtonStyle => ElevatedButton.styleFrom(
        backgroundColor: Colors.grey.shade300,
        foregroundColor: Colors.blueGrey.shade800,
        elevation: 7,
        shadowColor: Colors.black54,
        shape: StadiumBorder(),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );

  /// Shows the reset dialog.
  Future _showResetDialog() {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("You're about to reset the settings"),
          content: Text("Are you sure?"),
          actions: <Widget>[
            TextButton(
              child: Text("No, I'd like to keep the existing settings"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text("Yes", style: TextStyle(color: Colors.redAccent)),
              onPressed: () {
                _resetSettings();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Shows the reset dialog and executes the given callback afterwards.
  void _showResetDialogAndUpdate(void Function() cb) {
    _showResetDialog().then((_) => setState(cb));
  }

  /// Should save the settings to Shared Preferences.
  void _saveSettings();

  /// Should reset the settings.
  void _resetSettings();
}

class _HttpCallbackForwarderState
    extends _ForwarderScreenState<HttpCallbackForwarder> {
  HttpMethod _method = HttpMethod.POST;
  late Map<String, String> _uriParams;
  late Map<String, String> _jsonParams;
  late Map<String, String> _httpHeaders;

  /// Input textbox controller
  late TextEditingController _controller;

  /// Define the color of the borders
  late InputBorder _textFieldBorder;

  InputDecoration get _inputDecoration => InputDecoration(
      border: _textFieldBorder,
      enabledBorder: _textFieldBorder,
      focusedBorder: _textFieldBorder,
      hintText: "https://cb.example.com/endpoint",
      hintStyle: TextStyle(fontSize: 16));

  

  @override
  void initState() {
    super.initState();
    final fwd = widget.fwd.httpCallbackForwarder;
    _controller = TextEditingController(text: fwd?.callbackUrl);
    _method = fwd?.method ?? HttpMethod.POST;
    _uriParams = Map.from(fwd?.uriPayload ?? {});
    _jsonParams = Map.from(fwd?.jsonPayload ?? {});
    _httpHeaders = Map.from(fwd?.httpHeaders ?? {});
    _controller.addListener(_onTextChanged);
    setState(_onTextChanged);
  }

  /// Updates the border color depending on the field's value.
  void _onTextChanged() {
    setState(() {
      _textFieldBorder = OutlineInputBorder(
          borderSide: BorderSide(
              color: _checkValidUrl(_controller.text)
                  ? Colors.green
                  : Colors.red));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Http Callback Settings'),
      ),
      body: ResponsiveScaffoldBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text("Specify HTTP callback url and request method"),
            SizedBox(height: 8),
            Row(children: <Widget>[
              SizedBox(
                  width: 140,
                  child: Container(
                      margin: EdgeInsets.only(right: 8),
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4.0),
                        border: Border.all(
                            color: Colors.green,
                            style: BorderStyle.solid,
                            width: 1),
                      ),
                      child: PopupMenuButton<HttpMethod>(
                        position: PopupMenuPosition.under,
                        constraints:
                            BoxConstraints(minWidth: 140, maxWidth: 140),
                        onSelected: (method) =>
                            setState(() => _method = method),
                        itemBuilder: (context) => <PopupMenuEntry<HttpMethod>>[
                          PopupMenuItem<HttpMethod>(
                            value: HttpMethod.POST,
                            child: Center(
                                child: Text('POST',
                                    style: TextStyle(
                                        fontSize: 20, color: Colors.green))),
                          ),
                          PopupMenuItem<HttpMethod>(
                            value: HttpMethod.GET,
                            child: Center(
                                child: Text('GET',
                                    style: TextStyle(
                                        fontSize: 20, color: Colors.green))),
                          ),
                          PopupMenuItem<HttpMethod>(
                            value: HttpMethod.PUT,
                            child: Center(
                                child: Text('PUT',
                                    style: TextStyle(
                                        fontSize: 20, color: Colors.green))),
                          ),
                        ],
                        child: SizedBox(
                          height: 56,
                          child: Center(
                            child: Text(
                              _method.name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 20, color: Colors.green),
                            ),
                          ),
                        ),
                      ))),
              Expanded(
                  child: TextField(
                decoration: _inputDecoration,
                controller: _controller,
              ))
            ]),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: <Widget>[
                ElevatedButton(
                    child: Text('URI Params'),
                    style: _auxButtonStyle,
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => KeyValuePairSettingsScreen(
                            "URI Params", _uriParams))),
                ElevatedButton(
                    child: Text('JSON Payload'),
                    style: _auxButtonStyle,
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => KeyValuePairSettingsScreen(
                            "JSON Payload", _jsonParams))),
                ElevatedButton(
                    child: Text('Headers'),
                    style: _auxButtonStyle,
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => KeyValuePairSettingsScreen(
                            "HTTP Headers", _httpHeaders)))
              ],
            ),
            SizedBox(height: 8),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    style: _auxButtonStyle,
                    child: Text('Save'),
                    onPressed: !_checkValidUrl(_controller.text)
                        ? null
                        : () {
                            _saveSettings();
                            ScaffoldMessenger.of(context)
                                .showSnackBar(new SnackBar(
                              content: new Text("Saved"),
                            ));
                          }))
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showResetDialogAndUpdate(() {
          _controller.text =
              widget.fwd.httpCallbackForwarder?.callbackUrl ?? "";
        }),
        tooltip: "Reset Settings",
        child: Icon(Icons.clear),
      ),
    );
  }

  /// Updates the settings of the forwarder and dumps all forwarders to disk.
  @override
  void _saveSettings() async {
    widget.fwd.httpCallbackForwarder = HttpCallbackForwarder(_controller.text,
        method: _method,
        uriPayload: _uriParams,
        jsonPayload: _jsonParams,
        httpHeaders: _httpHeaders);
    widget.fwd.dumpToPrefs();
  }

  /// Removes the forwarder and dumps the rest of the forwarders to disk.
  @override
  void _resetSettings() async {
    _uriParams.clear();
    _jsonParams.clear();
    _httpHeaders.clear();
    widget.fwd.httpCallbackForwarder = null;
    widget.fwd.dumpToPrefs();
  }
}

class _TelegramBotForwarderScreen
    extends _ForwarderScreenState<TelegramBotForwarder> {
  /// Controls input boxes
  late TextEditingController _tokenController;
  late TextEditingController _chatIdController;
  late InputBorder _tokenTextFieldBorder;
  late InputBorder _chatIdTextFieldBorder;

  /// Define color of borders
  InputDecoration get _chatIdInputDecoration => InputDecoration(
        border: _chatIdTextFieldBorder,
        enabledBorder: _chatIdTextFieldBorder,
        focusedBorder: _chatIdTextFieldBorder,
        hintText: "E.g. 123456789",
      );

  InputDecoration get _tokenInputDecoration => InputDecoration(
        border: _tokenTextFieldBorder,
        enabledBorder: _tokenTextFieldBorder,
        focusedBorder: _tokenTextFieldBorder,
        hintText: "E.g. 123456789:AAMdsaoKe1Zw...",
      );

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(
        text: widget.fwd.telegramBotForwarder?.token ?? "");
    _chatIdController = TextEditingController(
        text: widget.fwd.telegramBotForwarder?.chatId.toString() ?? "");
    _tokenController.addListener(_onTokenTextChanged);
    _chatIdController.addListener(_onChatIdTextChanged);

    setState(() {
      _onTokenTextChanged();
      _onChatIdTextChanged();
    });
  }

  /// Updates the border color depending on the token's value.
  void _onTokenTextChanged() {
    setState(() {
      _tokenTextFieldBorder = OutlineInputBorder(
          borderSide: BorderSide(
              color: _tokenController.text.length > 0
                  ? Colors.green
                  : Colors.red));
    });
  }

  /// Updates the border color depending on chatId's value.
  void _onChatIdTextChanged() {
    setState(() {
      _chatIdTextFieldBorder = OutlineInputBorder(
          borderSide: BorderSide(
              color: int.tryParse(_chatIdController.text) != null
                  ? Colors.green
                  : Colors.red));
    });
  }

  /// Checks if all input fields contain valid values
  bool _checkAllIsValid() {
    return int.tryParse(_chatIdController.text) != null &&
        _tokenController.text.length > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Telegram Bot Settings'),
      ),
      body: ResponsiveScaffoldBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text("Specify your telegram chat id:"),
            SizedBox(height: 8),
            TextField(
              decoration: _chatIdInputDecoration,
              controller: _chatIdController,
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 12),
            Text("Specify your telegram token:"),
            SizedBox(height: 8),
            TextField(
              decoration: _tokenInputDecoration,
              controller: _tokenController,
            ),
            SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    style: _auxButtonStyle,
                    child: Text('Save'),
                    onPressed: !_checkAllIsValid()
                        ? null
                        : () {
                            _saveSettings();
                            ScaffoldMessenger.of(context)
                                .showSnackBar(new SnackBar(
                              content: new Text("Saved"),
                            ));
                          })),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showResetDialogAndUpdate(() {
          _tokenController.text = widget.fwd.telegramBotForwarder?.token ?? "";
          _chatIdController.text =
              widget.fwd.telegramBotForwarder?.chatId.toString() ?? "";
        }),
        tooltip: "Reset settings",
        child: Icon(Icons.clear),
      ),
    );
  }

  /// Updates the settings of the forwarder and dumps all forwarders to disk
  @override
  void _saveSettings() async {
    final chatId = int.tryParse(_chatIdController.text);
    if (chatId != null) {
      widget.fwd.telegramBotForwarder =
          TelegramBotForwarder(_tokenController.text, chatId);
    }
    widget.fwd.dumpToPrefs();
  }

  /// Sets the values of the forwarder to null
  @override
  void _resetSettings() async {
    widget.fwd.telegramBotForwarder = null;
    widget.fwd.dumpToPrefs();
  }
}

class _DeployedTelegramBotForwarderScreen
    extends _ForwarderScreenState<DeployedTelegramBotForwarder> {
  /// Textboxes
  late TextEditingController _tgHandleController;
  late TextEditingController _baseUrlController;
  late TextEditingController _botHandleController;

  late InputBorder _tgHandleTextFieldBorder;
  late InputBorder _baseUrlTextFieldBorder;
  late InputBorder _botHandleTextFieldBorder;

  /// Define the colors of the borders
  InputDecoration get _tgHandleInputDecoration => InputDecoration(
        border: _tgHandleTextFieldBorder,
        enabledBorder: _tgHandleTextFieldBorder,
        focusedBorder: _tgHandleTextFieldBorder,
        hintText: 'E.g. durov',
      );

  InputDecoration get _baseUrlInputDecoration => InputDecoration(
        border: _baseUrlTextFieldBorder,
        enabledBorder: _baseUrlTextFieldBorder,
        focusedBorder: _baseUrlTextFieldBorder,
        hintText: "E.g. https://example.com",
      );

  InputDecoration get _botHandleInputDecoration => InputDecoration(
        border: _botHandleTextFieldBorder,
        enabledBorder: _botHandleTextFieldBorder,
        focusedBorder: _botHandleTextFieldBorder,
        hintText: "E.g. your_personal_bot",
      );

  @override
  void initState() {
    super.initState();
    _tgHandleController = TextEditingController(
        text: widget.fwd.deployedTelegramBotForwarder?.tgHandle ?? "");
    _baseUrlController = TextEditingController(
        text: widget.fwd.deployedTelegramBotForwarder?.baseUrl ??
            "https://forwarder.whatever.team");
    _botHandleController = TextEditingController(
        text: widget.fwd.deployedTelegramBotForwarder?.botHandle ??
            "smsforwarderrobot");
    _tgHandleController.addListener(_onTgHandleTextChanged);
    _baseUrlController.addListener(_onBaseUrlTextChanged);
    _botHandleController.addListener(_onBotHandleTextChanged);

    setState(() {
      _onTgHandleTextChanged();
      _onBaseUrlTextChanged();
      _onBotHandleTextChanged();
    });
  }

  /// Updates the border color depending on the token's value
  void _onTgHandleTextChanged() {
    _tgHandleController.value = _tgHandleController.value.copyWith(
      text: _tgHandleController.text.replaceAll("@", ""),
      selection: _tgHandleController.selection,
      composing: _tgHandleController.value.composing,
    );
    setState(() {
      _tgHandleTextFieldBorder = OutlineInputBorder(
          borderSide: BorderSide(
              color: _checkValidHandle(_tgHandleController.text)
                  ? Colors.green
                  : Colors.red));
    });
  }

  /// Updates the border color depending on chatId's value
  void _onBaseUrlTextChanged() {
    setState(() {
      _baseUrlTextFieldBorder = OutlineInputBorder(
          borderSide: BorderSide(
              color: _checkValidUrl(_baseUrlController.text)
                  ? Colors.green
                  : Colors.red));
    });
  }

  /// Updates the border color depending on botHandle's value
  void _onBotHandleTextChanged() {
    _botHandleController.value = _botHandleController.value.copyWith(
      text: _botHandleController.text.replaceAll("@", ""),
      selection: _botHandleController.selection,
      composing: _botHandleController.value.composing,
    );
    setState(() {
      _botHandleTextFieldBorder = OutlineInputBorder(
          borderSide: BorderSide(
              color: _checkValidHandle(_botHandleController.text)
                  ? Colors.green
                  : Colors.red));
    });
  }

  /// Returns true if the handle length is correct
  bool _checkValidHandle(String handle) =>
      handle.length >= 5 && handle.length <= 32;

  /// Checks if all input fields contain valid values
  bool _checkAllIsValid() {
    return _checkValidHandle(_tgHandleController.text) &&
        _checkValidHandle(_botHandleController.text) &&
        _checkValidUrl(_baseUrlController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Deployed Bot Settings'),
      ),
      body: ResponsiveScaffoldBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text("Your SMS data will be sent to the broker server!",
                style: TextStyle(color: Colors.red, fontSize: 10)),
            Text("Specify your telegram @username:"),
            SizedBox(height: 6),
            TextField(
              decoration: _tgHandleInputDecoration,
              controller: _tgHandleController,
            ),
            SizedBox(height: 8),
            Text("Specify a broker url:"),
            SizedBox(height: 6),
            TextField(
              decoration: _baseUrlInputDecoration,
              controller: _baseUrlController,
            ),
            SizedBox(height: 8),
            Text("Specify the broker's bot @handle:"),
            SizedBox(height: 6),
            TextField(
              decoration: _botHandleInputDecoration,
              controller: _botHandleController,
            ),
            SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    style: _auxButtonStyle,
                    child: Text('Save'),
                    onPressed: !_checkAllIsValid()
                        ? null
                        : () {
                            _saveSettings();
                            ScaffoldMessenger.of(context)
                                .showSnackBar(new SnackBar(
                              content: new Text("Saved"),
                            ));
                            _openTelegramUrlInBrowser();
                          })),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showResetDialogAndUpdate(() {
          _tgHandleController.text =
              widget.fwd.deployedTelegramBotForwarder?.tgHandle ?? "";
          _baseUrlController.text =
              widget.fwd.deployedTelegramBotForwarder?.baseUrl ?? "";
        }),
        tooltip: "Reset Settings",
        child: Icon(Icons.clear),
      ),
    );
  }

  void _openTelegramUrlInBrowser() async {
    final urlString = widget.fwd.deployedTelegramBotForwarder?.getUrl();
    if (urlString == null) {
      return;
    }

    final url = Uri.parse(urlString);
    bool _canLaunch = await canLaunchUrl(url);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Open the link in the browser or copy to the clipboard:"),
          content: Text(urlString),
          actions: <Widget>[
            TextButton(
                child: Text("Open in Browser"),
                onPressed: _canLaunch
                    ? () {
                        launchUrl(url);
                        Navigator.of(context).pop();
                      }
                    : null),
            TextButton(
              child: Text("Copy", style: TextStyle(color: Colors.green)),
              onPressed: () {
                Clipboard.setData(new ClipboardData(text: urlString));
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Updates the settings of the forwarder and dumps all forwarders to disk
  @override
  void _saveSettings() async {
    widget.fwd.deployedTelegramBotForwarder = DeployedTelegramBotForwarder(
      _tgHandleController.text,
      baseUrl: _baseUrlController.text,
      botHandle: _botHandleController.text,
    );
    widget.fwd.dumpToPrefs();
  }

  /// Sets the value of the forwarder to null
  @override
  void _resetSettings() async {
    widget.fwd.deployedTelegramBotForwarder = null;
    widget.fwd.dumpToPrefs();
  }
}
