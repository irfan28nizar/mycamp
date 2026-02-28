import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:mycamp_app/core/storage/hive_initializer.dart';

class NavigationLocalDatabase {
  static const String _nodesKey = 'nodes_json';
  static const String _edgesKey = 'edges_json';
  static const String _placesKey = 'places_json';

  Box<dynamic> get _box => Hive.box<dynamic>(HiveInitializer.navigationBoxName);

  bool get hasData =>
      _box.containsKey(_nodesKey) &&
      _box.containsKey(_edgesKey) &&
      _box.containsKey(_placesKey);

  Future<void> saveData({
    required Map<String, dynamic> nodesJson,
    required Map<String, dynamic> edgesJson,
    required Map<String, dynamic> placesJson,
  }) async {
    await _box.put(_nodesKey, jsonEncode(nodesJson));
    await _box.put(_edgesKey, jsonEncode(edgesJson));
    await _box.put(_placesKey, jsonEncode(placesJson));
  }

  ({
    Map<String, dynamic> nodesJson,
    Map<String, dynamic> edgesJson,
    Map<String, dynamic> placesJson,
  })? readData() {
    if (!hasData) {
      return null;
    }

    final nodesRaw = _box.get(_nodesKey);
    final edgesRaw = _box.get(_edgesKey);
    final placesRaw = _box.get(_placesKey);
    if (nodesRaw is! String || edgesRaw is! String || placesRaw is! String) {
      return null;
    }

    final nodesJson = jsonDecode(nodesRaw);
    final edgesJson = jsonDecode(edgesRaw);
    final placesJson = jsonDecode(placesRaw);
    if (nodesJson is! Map<String, dynamic> ||
        edgesJson is! Map<String, dynamic> ||
        placesJson is! Map<String, dynamic>) {
      return null;
    }

    return (
      nodesJson: nodesJson,
      edgesJson: edgesJson,
      placesJson: placesJson,
    );
  }
}
