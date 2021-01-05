import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sms_forwarder/observer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sms/sms.dart';
import 'forwarding.dart';

void main() {
  runApp(new MyApp(SmsReceiver(), ForwarderObserver()));
}

class MyApp extends StatelessWidget {
  final SmsReceiver receiver;
  final ForwarderObserver obs;

  /// Instantiates application
  MyApp(this.receiver, this.obs) {
    // Set up listener
    // Loading of forwarders will be done in HomePage
    receiver.onSmsReceived.listen(obs.forward);
  }

  /// Creates main widget
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: 'Flutter Demo',
      theme: new ThemeData(
        primarySwatch: Colors.green,
      ),
      home: new HomePage(title: 'SMS forwarder', obs: this.obs),
    );
  }
}

class HomePage extends StatefulWidget {
  HomePage({Key key, this.title, this.obs}) : super(key: key);

  final String title;
  final ForwarderObserver obs;

  @override
  _HomePageState createState() => new _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MaterialColor _deployedBotBtnState = Colors.yellow;
  MaterialColor _tgBotBtnState = Colors.yellow;
  MaterialColor _callbackBtnState = Colors.yellow;

  @override
  void initState() {
    super.initState();

    // Load saved settings
    _loadForwarders();
  }

  /// Loads forwarders' settings and then updates buttons
  void _loadForwarders() async {
     var map = await widget.obs.loadFromPrefs();
     setState(() => _setForwardersColors(map));
  }

  void _setForwardersColors(Map map) {
    _deployedBotBtnState = map['DeployedTelegramBotForwarder']
        ? Colors.lightGreenAccent : Colors.yellow;
    _tgBotBtnState = map['TelegramBotForwarder']
        ? Colors.lightGreenAccent : Colors.yellow;
    _callbackBtnState = map['HttpCallbackForwarder']
        ? Colors.lightGreenAccent : Colors.yellow;
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text(widget.title),
      ),
      body: new Center(
        child: new Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Deployed bot forwarder button
            new ButtonTheme(
              minWidth: 320,
              height: 50,
              child: new FlatButton(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (context)
                            => ForwarderScreen<DeployedTelegramBotForwarder>(obs: widget.obs)
                      )).then((_)
                        => _setForwardersColors(widget.obs.reportReadiness())
                  ),
                  color: _deployedBotBtnState,
                  child: Text(
                      "Forwarding using deployed bot",
                      style: new TextStyle(fontSize: 20),
                  ),
              ),
            ),
            new Padding(padding: EdgeInsets.symmetric(vertical: 5)),
            // Telegram bot forwarder button
            new ButtonTheme(
              minWidth: 320,
              height: 50,
              child: new FlatButton(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (context)
                          => ForwarderScreen<TelegramBotForwarder>(obs: widget.obs)
                    )).then((_)
                      => _setForwardersColors(widget.obs.reportReadiness())
                ),
                color: _tgBotBtnState,
                child: Text(
                    "Forwarding using your tg bot",
                    style: new TextStyle(fontSize: 20),
                ),
              ),
            ),
            new Padding(padding: EdgeInsets.symmetric(vertical: 5)),
            // Http callback forwarder button
            new ButtonTheme(
              minWidth: 320,
              height: 50,
              child: new FlatButton(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (context)
                          => ForwarderScreen<HttpCallbackForwarder>(obs: widget.obs)
                    )).then((_)
                      => _setForwardersColors(widget.obs.reportReadiness())
                ),
                color: _callbackBtnState,
                child: Text(
                    "Forwarding using http callback",
                    style: new TextStyle(fontSize: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ForwarderScreen <T extends AbstractForwarder>
    extends StatefulWidget {
  const ForwarderScreen({Key key, this.obs})
      : super(key: key);

  final ForwarderObserver obs;

  /// Returns state for the provided forwarder
  static _ForwarderScreenState
  _selectStateClass <T extends AbstractForwarder>() {
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

abstract class _ForwarderScreenState <T extends AbstractForwarder>
    extends State<ForwarderScreen<T>> {
  /// Checks if given string is a valid url
  bool _checkValidUrl(String s) {
    var re = RegExp(
      r"https?:\/\/(((www\.)?[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}"
      r"\b([-a-zA-Z0-9@:%_\+.~#?&//=]*))|([0-9aA-zZ.]+:[0-9]+))",
      caseSensitive: false,
    );
    return re.hasMatch(s);
  }

  /// Shows reset dialog
  Future _showResetDialog() {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("You're about to reset the settings"),
          content: Text("Reset settings of the forwarder?"),
          actions: <Widget>[
            FlatButton(
              child: Text("Cancel"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            FlatButton(
              child: Text("Accept", style: TextStyle(color: Colors.redAccent)),
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

  /// Shows reset dialog and executes given callback after
  void _showResetDialogAndUpdate(void Function() cb) {
    _showResetDialog().then((_) => setState(cb));
  }

  /// Saves settings to Shared Preferences
  void _saveSettings();

  /// Resets settings of the forwarder
  void _resetSettings();
}

class _HttpCallbackForwarderState
    extends _ForwarderScreenState<HttpCallbackForwarder> {
  /// Controls input box
  TextEditingController _controller;
  /// Define color of borders
  InputBorder _textFieldBorder;
  InputDecoration get _inputDecoration => InputDecoration(
    border: _textFieldBorder,
    enabledBorder: _textFieldBorder,
    focusedBorder: _textFieldBorder,
    hintText: "E.g. https://cb.example.com/endpoint",
  );

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: widget.obs?.httpCallbackForwarder?.callbackUrl
    );
    _controller.addListener(_onTextChanged);
    setState(_onTextChanged);
  }

  /// Updates border color depending on field's value
  void _onTextChanged() {
    setState(() {
      _textFieldBorder = OutlineInputBorder(
        borderSide: BorderSide(color:
          _checkValidUrl(_controller.text) ? Colors.green : Colors.red
        )
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Http callback settings'),
      ),
      body: Builder(builder: (BuildContext context) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text("Specify http callback url:"),
              Padding(padding: EdgeInsets.symmetric(vertical: 5)),
              Container(
                width: 300,
                child: TextField(
                  decoration: _inputDecoration,
                  controller: _controller,
                ),
              ),
              RaisedButton(
                child: Text('Save'),
                onPressed: !_checkValidUrl(_controller.text) ?  null : () {
                  _saveSettings();
                  Scaffold.of(context).showSnackBar(new SnackBar(
                    content: new Text("Saved"),
                  ));
                }
              ),
            ],
          )
        );
      }),
     floatingActionButton: FloatingActionButton(
       onPressed: () => _showResetDialogAndUpdate(() {
         _controller.text = widget.obs.httpCallbackForwarder?.callbackUrl ?? "";
       }),
       tooltip: "Reset settings",
       child: Icon(Icons.clear),
     ),
    );
  }

  /// Updates settings of the forwarder and dumps forwarders to disk
  @override
  void _saveSettings() {
    widget
        ?.obs
        ?.httpCallbackForwarder = HttpCallbackForwarder(_controller.text);
    widget?.obs?.dumpToPrefs();
  }

  /// Sets value of the forwarder to null
  @override
  void _resetSettings() {
    widget
        ?.obs
        ?.httpCallbackForwarder = null;
    widget?.obs?.dumpToPrefs();
  }
}

class _TelegramBotForwarderScreen
    extends _ForwarderScreenState<TelegramBotForwarder> {
  /// Controls input boxes
  TextEditingController _tokenController;
  TextEditingController _chatIdController;
  InputBorder _tokenTextFieldBorder;
  InputBorder _chatIdTextFieldBorder;

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
        text: widget.obs?.telegramBotForwarder?.token ?? ""
    );
    _chatIdController = TextEditingController(
      text: widget.obs?.telegramBotForwarder?.chatId?.toString() ?? ""
    );
    _tokenController.addListener(_onTokenTextChanged);
    _chatIdController.addListener(_onChatIdTextChanged);

    setState(() {
      _onTokenTextChanged();
      _onChatIdTextChanged();
    });
  }

  /// Updates border color depending on token's value
  void _onTokenTextChanged() {
    setState(() {
      _tokenTextFieldBorder = OutlineInputBorder(
          borderSide: BorderSide(color:
            _tokenController.text.length > 0 ? Colors.green : Colors.red
          )
      );
    });
  }

  /// Updates border color depending on chatId's value
  void _onChatIdTextChanged() {
    setState(() {
      _chatIdTextFieldBorder = OutlineInputBorder(
          borderSide: BorderSide(color:
            int.tryParse(_chatIdController.text) != null
                ? Colors.green : Colors.red
          )
      );
    });
  }

  /// Checks if all input fields contain valid values
  bool _checkAllIsValid() {
    if (_chatIdController == null || _tokenController == null) return false;
    return int.tryParse(_chatIdController.text) != null &&
           _tokenController.text.length > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Telegram bot settings'),
      ),
      body: Builder(builder: (BuildContext context) {
        return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text("Specify your telegram chat id:"),
                Padding(padding: EdgeInsets.symmetric(vertical: 5)),
                Container(
                  width: 300,
                  child: TextField(
                    decoration: _chatIdInputDecoration,
                    controller: _chatIdController,
                  ),
                ),
                Padding(padding: EdgeInsets.symmetric(vertical: 5)),
                Text("Specify your telegram token:"),
                Padding(padding: EdgeInsets.symmetric(vertical: 5)),
                Container(
                  width: 300,
                  child: TextField(
                    decoration: _tokenInputDecoration,
                    controller: _tokenController,
                  ),
                ),
                RaisedButton(
                    child: Text('Save'),
                    onPressed: !_checkAllIsValid() ?  null : () {
                      _saveSettings();
                      Scaffold.of(context).showSnackBar(new SnackBar(
                        content: new Text("Saved"),
                      ));
                    }
                ),
              ],
            )
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showResetDialogAndUpdate(() {
          _tokenController.text = widget.obs?.telegramBotForwarder?.token ?? "";
          _chatIdController.text =
              widget.obs?.telegramBotForwarder?.chatId?.toString() ?? "";
        }),
        tooltip: "Reset settings",
        child: Icon(Icons.clear),
      ),
    );
  }

  /// Updates settings of the forwarder and dumps forwarders to disk
  @override
  void _saveSettings() {
    widget
        ?.obs
        ?.telegramBotForwarder =
        TelegramBotForwarder(
            _tokenController.text,
            int.tryParse(_chatIdController.text)
        );
    widget?.obs?.dumpToPrefs();
  }

  /// Sets value of the forwarder to null
  @override
  void _resetSettings() {
    widget
        ?.obs
        ?.telegramBotForwarder = null;
    widget?.obs?.dumpToPrefs();
  }
}

class _DeployedTelegramBotForwarderScreen
    extends _ForwarderScreenState<DeployedTelegramBotForwarder> {
  /// Controls input boxes
  TextEditingController _tgHandleController;
  TextEditingController _baseUrlController;
  TextEditingController _botHandleController;

  InputBorder _tgHandleTextFieldBorder;
  InputBorder _baseUrlTextFieldBorder;
  InputBorder _botHandleTextFieldBorder;

  /// Define colors of borders
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
        text: widget.obs?.deployedTelegramBotForwarder?.tgHandle ?? ""
    );
    _baseUrlController = TextEditingController(
        text: widget.obs?.deployedTelegramBotForwarder?.baseUrl ??
              "https://forwarder.whatever.team"
    );
    _botHandleController = TextEditingController(
        text: widget.obs?.deployedTelegramBotForwarder?.botHandle ??
            "smsforwarderrobot"
    );
    _tgHandleController.addListener(_onTgHandleTextChanged);
    _baseUrlController.addListener(_onBaseUrlTextChanged);
    _botHandleController.addListener(_onBotHandleTextChanged);

    setState(() {
      _onTgHandleTextChanged();
      _onBaseUrlTextChanged();
      _onBotHandleTextChanged();
    });
  }

  /// Updates border color depending on token's value
  void _onTgHandleTextChanged() {
    _tgHandleController.value = _tgHandleController.value.copyWith(
        text: _tgHandleController.text.replaceAll("@", ""),
        selection: _tgHandleController.selection,
        composing: _tgHandleController.value.composing,
    );
    setState(() {
      _tgHandleTextFieldBorder = OutlineInputBorder(
          borderSide: BorderSide(color:
              _checkValidHandle(_tgHandleController.text) ?
                Colors.green : Colors.red
          )
      );
    });
  }

  /// Updates border color depending on chatId's value
  void _onBaseUrlTextChanged() {
    setState(() {
      _baseUrlTextFieldBorder = OutlineInputBorder(
          borderSide: BorderSide(color:
          _checkValidUrl(_baseUrlController.text) ? Colors.green : Colors.red
          )
      );
    });
  }

  /// Updates border color depending on botHandle's value
  void _onBotHandleTextChanged() {
    _botHandleController.value = _botHandleController.value.copyWith(
      text: _botHandleController.text.replaceAll("@", ""),
      selection: _botHandleController.selection,
      composing: _botHandleController.value.composing,
    );
    setState(() {
      _botHandleTextFieldBorder = OutlineInputBorder(
          borderSide: BorderSide(color:
            _checkValidHandle(_botHandleController.text) ?
              Colors.green : Colors.red
          )
      );
    });

  }

  /// Returns true if handle matches required length
  bool _checkValidHandle(String handle)
    => handle.length >= 5 && handle.length <= 32;

  /// Checks if all input fields contain valid values
  bool _checkAllIsValid() {
    if (_baseUrlController   == null ||
        _tgHandleController  == null ||
        _botHandleController == null) return false;
    return _checkValidHandle(_tgHandleController.text)  &&
           _checkValidHandle(_botHandleController.text) &&
           _checkValidUrl(_baseUrlController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Deployed bot settings'),
      ),
      body: Builder(builder: (BuildContext context) {
        return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                    "Your SMS data will be sent to the broker server!",
                    style: TextStyle(color: Colors.red, fontSize: 10)
                ),
                Text("Specify your telegram @username:"),
                Padding(padding: EdgeInsets.symmetric(vertical: 3)),
                Container(
                  width: 300,
                  child: TextField(
                    decoration: _tgHandleInputDecoration,
                    controller: _tgHandleController,
                  ),
                ),
                Padding(padding: EdgeInsets.symmetric(vertical: 3)),
                Text("Specify broker url:"),
                Padding(padding: EdgeInsets.symmetric(vertical: 3)),
                Container(
                  width: 300,
                  child: TextField(
                    decoration: _baseUrlInputDecoration,
                    controller: _baseUrlController,
                  ),
                ),
                Padding(padding: EdgeInsets.symmetric(vertical: 4)),
                Text("Specify bot @handle:"),
                Padding(padding: EdgeInsets.symmetric(vertical: 4)),
                Container(
                  width: 300,
                  child: TextField(
                    decoration: _botHandleInputDecoration,
                    controller: _botHandleController,
                  ),
                ),
                RaisedButton(
                    child: Text('Save'),
                    onPressed: !_checkAllIsValid() ?  null : () {
                      _saveSettings();
                      Scaffold.of(context).showSnackBar(new SnackBar(
                        content: new Text("Saved"),
                      ));
                      _openTelegramUrlInBrowser();
                    }
                ),
              ],
            )
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showResetDialogAndUpdate(() {
          _tgHandleController.text =
              widget.obs.deployedTelegramBotForwarder?.tgHandle ?? "";
          _baseUrlController.text =
              widget.obs.deployedTelegramBotForwarder?.baseUrl ?? "";
        }),
        tooltip: "Reset settings",
        child: Icon(Icons.clear),
      ),
    );
  }

  void _openTelegramUrlInBrowser() async {
    String url = widget.obs?.deployedTelegramBotForwarder?.getUrl();
    bool _canLaunch = await canLaunch(url);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Open link in the browser or copy to clipboard:"),
          content: Text(url),
          actions: <Widget>[
            FlatButton(
              child: Text("Open in browser"),
              onPressed: _canLaunch ? () {
                launch(url);
                Navigator.of(context).pop();
              } : null
            ),
            FlatButton(
              child: Text("Copy",
                  style: TextStyle(color: Colors.green)
              ),
              onPressed: () {
                Clipboard.setData(new ClipboardData(text: url));
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Updates settings of the forwarder and dumps forwarders to disk
  @override
  void _saveSettings() {
    widget
        ?.obs
        ?.deployedTelegramBotForwarder =
        DeployedTelegramBotForwarder(
            _tgHandleController.text,
            baseUrl: _baseUrlController.text,
            botHandle: _botHandleController.text,
        );
    widget?.obs?.dumpToPrefs();
  }

  /// Sets value of the forwarder to null
  @override
  void _resetSettings() {
    widget
        ?.obs
        ?.deployedTelegramBotForwarder = null;
    widget?.obs?.dumpToPrefs();
  }
}
