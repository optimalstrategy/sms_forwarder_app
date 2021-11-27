import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/background_forwarder.dart';
import 'package:telephony/telephony.dart';

class SettingStrings {
  static final String launchOnStartup = "launch_on_startup";
}

/// A screen with the App's settings.
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen(this.fwd, {Key key}) : super(key: key);

  final BackgroundForwarder fwd;

  @override
  _AppSettingsScreenState createState() => _AppSettingsScreenState(this.fwd);
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  _AppSettingsScreenState(this.fwd);

  final BackgroundForwarder fwd;

  OutlineInputBorder _testMessageBorder;
  TextEditingController _testMessageController;

  bool _launchOnStartup = true;
  Map<String, bool> _forwardingResults;

  @override
  void initState() {
    super.initState();

    _testMessageController = new TextEditingController(text: "Test message");
    _testMessageController.addListener(_onTextChanged);
    setState(_onTextChanged);

    _forwardingResults = {
      "HttpCallbackForwarder": null,
      "TelegramBotForwarder": null,
      "DeployedTelegramBotForwarder": null,
    };

    fwd.loadFromPrefs();
    SharedPreferences.getInstance().then((prefs) {
      setState(() {
        _launchOnStartup =
            prefs.getBool(SettingStrings.launchOnStartup) ?? true;
      });
    });
  }

  void _onTextChanged() {
    setState(() {
      _testMessageBorder = OutlineInputBorder(
          borderSide: BorderSide(
              color: _testMessageController.text.length > 0
                  ? Colors.green
                  : Colors.red));
    });
  }

  void _updatePreferences() async {
    final instance = await SharedPreferences.getInstance();
    instance.setBool(SettingStrings.launchOnStartup, _launchOnStartup);
  }

  void _testForwarders() async {
    // ignore: invalid_use_of_visible_for_testing_member
    final results = await fwd.mgr.forward(SmsMessage.fromMap({
      "address": "SmsForwarder",
      "body": _testMessageController.text,
      "date": DateTime.now().millisecondsSinceEpoch.toString(),
    }, [
      SmsColumn.ADDRESS,
      SmsColumn.BODY,
      SmsColumn.DATE,
    ]));
    setState(() {
      _forwardingResults = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = _forwardingResults.keys.toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text("App Settings"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            Row(children: <Widget>[
              Text(
                "Launch on Startup: ",
                style: TextStyle(fontSize: 20),
              ),
              Switch(
                activeColor: Colors.green,
                value: _launchOnStartup,
                onChanged: (value) {
                  setState(() => _launchOnStartup = value);
                  _updatePreferences();
                },
              )
            ], mainAxisAlignment: MainAxisAlignment.spaceAround),
            Column(children: <Widget>[
              Container(
                child: TextField(
                  controller: _testMessageController,
                  decoration: InputDecoration(
                      border: _testMessageBorder,
                      enabledBorder: _testMessageBorder,
                      disabledBorder: _testMessageBorder,
                      hintText: "Enter a test message"),
                ),
                width: 350,
              ),
              ElevatedButton(
                child: Text('Send Test Message'),
                onPressed: _testForwarders,
              ),
              ListView.builder(
                padding: const EdgeInsets.all(8),
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final forwarder = results[index];
                  final result = _forwardingResults[forwarder];
                  Color color;
                  if (result == null) {
                    color = Colors.grey;
                  } else if (result) {
                    color = Colors.green;
                  } else {
                    color = Colors.red[200];
                  }
                  return Container(
                    height: 50,
                    child: Center(child: Text(forwarder)),
                    decoration:
                        BoxDecoration(border: Border.all(), color: color),
                    margin: EdgeInsets.symmetric(vertical: 1),
                  );
                },
              )
            ])
          ],
        ),
      ),
    );
  }
}
