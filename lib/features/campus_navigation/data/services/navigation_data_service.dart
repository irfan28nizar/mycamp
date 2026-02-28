import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:mycamp_app/features/campus_navigation/data/models/edge_model.dart';
import 'package:mycamp_app/features/campus_navigation/data/models/node_model.dart';
import 'package:mycamp_app/features/campus_navigation/data/models/place_model.dart';
import 'package:mycamp_app/features/campus_navigation/data/services/navigation_local_database.dart';

class NavigationDataService {
  final NavigationLocalDatabase _localDatabase = NavigationLocalDatabase();

  List<NodeModel> _nodes = <NodeModel>[];
  List<EdgeModel> _edges = <EdgeModel>[];
  List<PlaceModel> _places = <PlaceModel>[];

  List<NodeModel> get nodes => _nodes;
  List<EdgeModel> get edges => _edges;
  List<PlaceModel> get places => _places;

  Future<void> initialize() async {
    try {
      final results = await Future.wait<String>([
        rootBundle.loadString('assets/maps/nodes.json'),
        rootBundle.loadString('assets/maps/edges.json'),
        rootBundle.loadString('assets/maps/places.json'),
      ]);

      final nodesJson = jsonDecode(results[0]) as Map<String, dynamic>;
      final edgesJson = jsonDecode(results[1]) as Map<String, dynamic>;
      final placesJson = jsonDecode(results[2]) as Map<String, dynamic>;

      _loadFromJsonMaps(
        nodesJson: nodesJson,
        edgesJson: edgesJson,
        placesJson: placesJson,
      );

      await _localDatabase.saveData(
        nodesJson: nodesJson,
        edgesJson: edgesJson,
        placesJson: placesJson,
      );
      return;
    } on Object {
      final cached = _localDatabase.readData();
      if (cached != null) {
        _loadFromJsonMaps(
          nodesJson: cached.nodesJson,
          edgesJson: cached.edgesJson,
          placesJson: cached.placesJson,
        );
        return;
      }
      rethrow;
    }
  }

  void _loadFromJsonMaps({
    required Map<String, dynamic> nodesJson,
    required Map<String, dynamic> edgesJson,
    required Map<String, dynamic> placesJson,
  }) {
    final rawNodes = (nodesJson['nodes'] as List<dynamic>? ?? <dynamic>[]);
    final edgeCollectionType = edgesJson['type'];
    final rawEdges = edgesJson['features'];
    if (edgeCollectionType != 'FeatureCollection' || rawEdges is! List<dynamic>) {
      throw const FormatException('edges.json must be a GeoJSON FeatureCollection');
    }
    final rawPlaces = (placesJson['places'] as List<dynamic>? ?? <dynamic>[]);

    _nodes = rawNodes
        .map((item) => NodeModel.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    _edges = rawEdges
        .map((item) => EdgeModel.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    _places = rawPlaces
        .map((item) => PlaceModel.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }
}
