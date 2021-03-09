import 'package:flutter/material.dart';

/// A screen with a vertical list of key-value pairs. Pairs may be removed
/// and created dynamically. The widget uses the provided kvMap as its baking storage,
/// modifying it in the process.
class KeyValuePairSettingsScreen extends StatefulWidget {
  const KeyValuePairSettingsScreen(this.title, this.kvMap, {Key key})
      : super(key: key);

  /// The screen title.
  final String title;

  /// The baking map of key-value pairs.
  final Map<String, String> kvMap;

  @override
  _KeyValuePairScreenState createState() =>
      _KeyValuePairScreenState(title, kvMap);
}

/// The state of the key-value settings screen.
class _KeyValuePairScreenState extends State<KeyValuePairSettingsScreen> {
  _KeyValuePairScreenState(this.title, this.kvMap);

  /// The screen title.
  final String title;

  /// The baking map of key-value pairs.
  Map<String, String> kvMap;

  /// The list of pair widgets currently being displayed.
  List<Widget> pairs = [];

  /// Clears the list of tne rendered key-value pairs and creates a new one
  /// from the baking map.
  void buildKeyValueRows() {
    pairs.clear();
    for (var entry in kvMap.entries) {
      if (entry.key == "") continue;
      addKvWidget(key: entry.key);
    }
  }

  /// Adds a new widget and a padding to the list of key-value pairs.
  void addKvWidget({String key}) {
    // Note that the key, UniqueKey(), is required to ensure that the widgets
    // are updated correctly,
    pairs.add(new _KeyValuePairWidget(this, kvMap,
        key: UniqueKey(), initialKey: key));
    pairs.add(Padding(padding: EdgeInsets.symmetric(vertical: 5)));
  }

  @override
  void initState() {
    super.initState();
    setState(() => buildKeyValueRows());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: pairs +
                <Widget>[
                  FloatingActionButton(
                    onPressed: () => {setState(() => addKvWidget(key: null))},
                    tooltip: 'Add New Key Value Pair',
                    child: Icon(Icons.add),
                  ),
                ]),
      ),
    );
  }
}

/// A widget that holds a single key value pair.
class _KeyValuePairWidget extends StatefulWidget {
  const _KeyValuePairWidget(this._parentState, this.kvMap,
      {Key key, this.initialKey})
      : super(key: key);

  /// The state of the parent settings screen widget.
  final _KeyValuePairScreenState _parentState;

  /// A reference to the baking map.
  final Map kvMap;

  /// The initial key value.
  final String initialKey;

  @override
  State<StatefulWidget> createState() =>
      _KeyValuePairWidgetState(_parentState, kvMap, initialKey ?? "");
}

class _KeyValuePairWidgetState extends State<_KeyValuePairWidget> {
  _KeyValuePairWidgetState(this._parentState, this.kvMap, this.key) : super();

  /// The state of the parent settings screen widget.
  final _KeyValuePairScreenState _parentState;

  /// A reference to the baking map baking map.
  final Map kvMap;

  /// The currently displayed key / previous key value.
  String key = "";

  /// The currently displayed value / previous `value` value.
  String value;

  /// Whether to allow editing the value.
  bool _valueEnabled = true;

  // UI controllers, borders, and decorations.
  TextEditingController _keyController;
  TextEditingController _valueController;
  InputBorder _keyBorder;
  InputBorder _valueBorder;

  InputDecoration get _keyInputDecoration => InputDecoration(
        border: _keyBorder,
        enabledBorder: _keyBorder,
        focusedBorder: _keyBorder,
        hintText: "api_secret",
      );

  InputDecoration get _valueInputDecoration => InputDecoration(
        border: _valueBorder,
        enabledBorder: _valueBorder,
        focusedBorder: _valueBorder,
        hintText: "e.g. hunter2",
      );

  @override
  void initState() {
    super.initState();

    _keyController = TextEditingController(text: key);
    _valueController =
        TextEditingController(text: key.isNotEmpty ? (kvMap[key] ?? "") : "");

    _keyController.addListener(_onKeyChanged);
    _valueController.addListener(_onValueChanged);

    setState(() {
      _onKeyChanged();
      _onValueChanged();
    });
  }

  void _onKeyChanged() {
    var newKey = _keyController.value.text;
    var color = Colors.green;
    var enabled = true;

    // If newKey is empty and key is not, the user has erased the name.
    if (newKey.isEmpty) {
      kvMap.remove(key);
      // Make the border red if the key is missing but the value is present
      if (value != null) color = Colors.red;
      // If the key is non-empty and isn't already in the map, update the map
      // and remove the old entry.
    } else if (newKey.isNotEmpty && !kvMap.containsKey(newKey)) {
      value = kvMap.remove(this.key);
      this.key = newKey;
      kvMap[this.key] = value;

      // Otherwise, the key must either be already used by another entry
      // or be identical to the current key. We want to reject the former.
    } else if (newKey != this.key) {
      // The previous entry still needs to be cleared
      value = kvMap.remove(this.key);
      enabled = false;
      color = Colors.red;
    }

    setState(() {
      _valueEnabled = enabled;
      _keyBorder = OutlineInputBorder(borderSide: BorderSide(color: color));
    });
  }

  void _onValueChanged() {
    value = _valueController.value.text;
    if (key.isNotEmpty) kvMap[key] = value;

    setState(() {
      _valueBorder =
          OutlineInputBorder(borderSide: BorderSide(color: Colors.green));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
          width: 125,
          child: TextField(
              decoration: _keyInputDecoration, controller: _keyController)),
      Padding(padding: EdgeInsets.symmetric(horizontal: 5)),
      Container(
          width: 200,
          child: TextField(
              enabled: _valueEnabled,
              decoration: _valueInputDecoration,
              controller: _valueController)),
      IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.delete),
        iconSize: 24.0,
        color: Colors.red,
        onPressed: () {
          _parentState.setState(() {
            kvMap.remove(key);
            _parentState.buildKeyValueRows();
          });
        },
      ),
    ]);
  }
}
