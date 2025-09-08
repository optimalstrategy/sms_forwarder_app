import 'package:flutter/material.dart';
import 'responsive.dart';

/// A screen with a vertical list of key-value pairs. Pairs may be removed
/// and created dynamically. The widget uses the provided kvMap as its baking storage,
/// modifying it according to the user's actions.
class KeyValuePairSettingsScreen extends StatefulWidget {
  const KeyValuePairSettingsScreen(this.title, this.kvMap, {Key? key})
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
  void addKvWidget({String? key}) {
    // Note that the key, UniqueKey(), is required to ensure that the widgets
    // are updated correctly,
    pairs.add(new _KeyValuePairWidget(this, kvMap,
        key: UniqueKey(), initialKey: key));
    pairs.add(Padding(padding: EdgeInsets.symmetric(vertical: 5)));
  }

  /// Removes a specific key-value pair widget (by its Widget Key) and its
  /// trailing padding without rebuilding all pairs from kvMap. Optionally also
  /// removes the corresponding entry from kvMap using [dataKey].
  void removePairByWidgetKey(Key? widgetKey, {String? dataKey}) {
    if (widgetKey == null) return;
    setState(() {
      if (dataKey != null && dataKey.isNotEmpty) {
        kvMap.remove(dataKey);
      }

      final idx = pairs.indexWhere((w) => w.key == widgetKey);
      if (idx >= 0) {
        pairs.removeAt(idx);
        if (idx < pairs.length && pairs[idx] is Padding) {
          pairs.removeAt(idx);
        } else if (idx - 1 >= 0 && pairs[idx - 1] is Padding) {
          pairs.removeAt(idx - 1);
        }
      }
    });
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
      body: ResponsiveScaffoldBody(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: pairs +
                <Widget>[
                  SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.add),
                      label: Text('Add New Key Value Pair'),
                      onPressed: () => {setState(() => addKvWidget(key: null))},
                    ),
                  ),
                ]),
      ),
    );
  }
}

/// A widget that holds a single key value pair.
class _KeyValuePairWidget extends StatefulWidget {
  const _KeyValuePairWidget(this._parentState, this.kvMap,
      {required Key key, this.initialKey})
      : super(key: key);

  /// The state of the parent settings screen widget.
  final _KeyValuePairScreenState _parentState;

  /// A reference to the baking map.
  final Map kvMap;

  /// The initial key value.
  final String? initialKey;

  @override
  State<StatefulWidget> createState() =>
      _KeyValuePairWidgetState(_parentState, kvMap, initialKey ?? "");
}

class _KeyValuePairWidgetState extends State<_KeyValuePairWidget> {
  _KeyValuePairWidgetState(this._parentState, this.kvMap, this.key)
      : _initialKey = key,
        super();

  /// The state of the parent settings screen widget.
  final _KeyValuePairScreenState _parentState;

  /// A reference to the baking map baking map.
  final Map kvMap;

  /// The currently displayed key / previous key value.
  String key = "";

  /// The originally provided key (used to remove from kvMap if unchanged)
  final String _initialKey;

  /// The currently displayed value / previous `value` value.
  String? value;

  /// Whether to allow editing the value.
  bool _valueEnabled = true;

  // UI controllers, borders, and decorations.
  late TextEditingController _keyController;
  late TextEditingController _valueController;
  late InputBorder _keyBorder;
  late InputBorder _valueBorder;

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
      if (value != null) {
        color = Colors.red;
      }
      // If the key is non-empty and isn't already in the map, update the map
      // and remove the old entry.
    } else if (newKey.isNotEmpty && !kvMap.containsKey(newKey)) {
      value = kvMap.remove(this.key);
      this.key = newKey;
      kvMap[this.key] = value;

      // Otherwise, the key must either be already used by another entry
      // or be identical to the current key. We want to reject the former.
    } else if (newKey != this.key && this.key != "") {
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
      if (value == null || value == "") {
        _valueBorder =
            OutlineInputBorder(borderSide: BorderSide(color: Colors.red));
        return;
      }

      _keyBorder = OutlineInputBorder(
          borderSide:
              BorderSide(color: key.isNotEmpty ? Colors.green : Colors.red));
      _valueBorder =
          OutlineInputBorder(borderSide: BorderSide(color: Colors.green));
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 420;
      final keyFieldBox = TextField(
          decoration: _keyInputDecoration, controller: _keyController);
      final valueFieldBox = TextField(
          enabled: _valueEnabled,
          decoration: _valueInputDecoration,
          controller: _valueController);
      final deleteBtn = IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.delete),
        iconSize: 24.0,
        color: Colors.red,
        onPressed: () {
          // Remove this pair only, and its kvMap entry based on current key
          // or fallback to initial key if current key is empty.
          final dataKey = key.isNotEmpty ? key : _initialKey;
          _parentState.removePairByWidgetKey(widget.key, dataKey: dataKey);
        },
      );

      if (isNarrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            keyFieldBox,
            SizedBox(height: 6),
            valueFieldBox,
            Align(alignment: Alignment.centerRight, child: deleteBtn),
          ],
        );
      }
      return Row(children: [
        Expanded(flex: 4, child: keyFieldBox),
        SizedBox(width: 8),
        Expanded(flex: 7, child: valueFieldBox),
        deleteBtn,
      ]);
    });
  }
}
