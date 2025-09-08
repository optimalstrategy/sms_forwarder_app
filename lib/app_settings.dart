import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/background_forwarder.dart';
import 'package:another_telephony/telephony.dart';
import 'package:sms_forwarder/retry_defs.dart';
import 'responsive.dart';
import 'forwarding_queue.dart';
import 'queue_screen.dart';

class SettingStrings {
  static final String launchOnStartup = "launch_on_startup";
}

/// A screen with the App's settings.
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen(this.fwd, {Key? key}) : super(key: key);

  final BackgroundForwarder fwd;

  @override
  _AppSettingsScreenState createState() => _AppSettingsScreenState(this.fwd);
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  _AppSettingsScreenState(this.fwd);

  final BackgroundForwarder fwd;

  OutlineInputBorder? _testMessageBorder;
  late TextEditingController _testMessageController;

  bool _launchOnStartup = true;
  late Map<String, bool?> _forwardingResults;
  QueueCounts? _queueCounts;

  /// Common style for auxiliary action buttons to match Save/aux buttons.
  ButtonStyle get _auxButtonStyle => ElevatedButton.styleFrom(
        backgroundColor: Colors.grey.shade300,
        foregroundColor: Colors.blueGrey.shade800,
        elevation: 7,
        shadowColor: Colors.black54,
        shape: StadiumBorder(),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );

  @override
  void initState() {
    super.initState();

    _testMessageController = new TextEditingController(text: "Test message");
    _testMessageController.addListener(_onTextChanged);
    setState(_onTextChanged);

    _forwardingResults = {
      kFwdHttp: null,
      kFwdTg: null,
      kFwdDeployed: null,
    };

    fwd.loadFromPrefs();
    SharedPreferences.getInstance().then((prefs) {
      setState(() {
        _launchOnStartup =
            prefs.getBool(SettingStrings.launchOnStartup) ?? true;
      });
    });
    _loadQueueCounts();
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
    if (mounted) {
      setState(() {
        _forwardingResults = results;
      });
    }
  }

  Future<void> _loadQueueCounts() async {
    final counts = await ForwardingRequestQueue().getCounts();
    if (mounted) setState(() => _queueCounts = counts);
  }

  void _openQueue() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const QueueScreen()))
        .then((_) => _loadQueueCounts());
  }

  Widget _buildQueueSummary() {
    final c = _queueCounts;
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        title: Text('Forwarding Queue', style: TextStyle(fontSize: 18)),
        subtitle: c == null
            ? Text('Loading...')
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _countChip('Pending', c.pending, Colors.orange.shade600),
                  _countChip('Success', c.success, Colors.green.shade600),
                  _countChip(
                      'Partial', c.partialFailure, Colors.amber.shade700),
                  _countChip('Failed', c.failure, Colors.red.shade400),
                ],
              ),
        trailing: TextButton.icon(
          icon: Icon(Icons.list_alt),
          label: Text('Open'),
          onPressed: _openQueue,
        ),
      ),
    );
  }

  Widget _countChip(String label, int count, Color color) {
    return Chip(
      backgroundColor: color,
      label: Text('$label: $count', style: TextStyle(color: Colors.white)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _forwardingResults.keys.toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text("App Settings"),
      ),
      body: ResponsiveScaffoldBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                "Launch on Startup",
                style: TextStyle(fontSize: 20),
              ),
              value: _launchOnStartup,
              activeThumbColor: Colors.green,
              onChanged: (value) {
                setState(() => _launchOnStartup = value);
                _updatePreferences();
              },
            ),
            SizedBox(height: 8),
            TextField(
              controller: _testMessageController,
              decoration: InputDecoration(
                  border: _testMessageBorder,
                  enabledBorder: _testMessageBorder,
                  disabledBorder: _testMessageBorder,
                  hintText: "Enter a test message"),
            ),
            SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: _auxButtonStyle,
                child: Text('Send Test Message'),
                onPressed: _testForwarders,
              ),
            ),
            ListView.builder(
              padding: const EdgeInsets.all(8),
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
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
                  color = Colors.red.shade200;
                }
                return Container(
                  height: 50,
                  child: Center(child: Text(forwarder)),
                  decoration: BoxDecoration(border: Border.all(), color: color),
                  margin: EdgeInsets.symmetric(vertical: 1),
                );
              },
            ),
            _buildQueueSummary(),
          ],
        ),
      ),
    );
  }
}
