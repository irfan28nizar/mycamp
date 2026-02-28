import 'package:latlong2/latlong.dart';

class EdgeModel {
  const EdgeModel({
    required this.from,
    required this.to,
    required this.type,
    required this.geometry,
  });

  final int from;
  final int to;
  final String type;
  final List<LatLng> geometry;

  factory EdgeModel.fromJson(Map<String, dynamic> json) {
    final featureType = json['type'];
    final properties = json['properties'];
    final geometryJson = json['geometry'];

    if (featureType != 'Feature' ||
        properties is! Map<String, dynamic> ||
        geometryJson is! Map<String, dynamic>) {
      throw const FormatException('Invalid GeoJSON edge feature');
    }

    final from = properties['from'];
    final to = properties['to'];
    final type = properties['type'];
    if (from is! int || to is! int || type is! String) {
      throw const FormatException('Invalid edge properties');
    }
    final normalizedType = type.toLowerCase();
    if (normalizedType != 'walk' && normalizedType != 'drive') {
      throw const FormatException('Edge type must be "walk" or "drive"');
    }

    final geometry = <LatLng>[];
    final geometryType = geometryJson['type'];
    final coordinates = geometryJson['coordinates'];

    if (geometryType != 'LineString' || coordinates is! List) {
      throw const FormatException('Edge geometry must be a LineString');
    }

    for (final point in coordinates) {
      if (point is! List || point.length < 2) {
        throw const FormatException('Invalid LineString coordinate');
      }
      final lng = point[0];
      final lat = point[1];
      if (lat is! num || lng is! num) {
        throw const FormatException('Invalid LineString coordinate values');
      }
      geometry.add(LatLng(lat.toDouble(), lng.toDouble()));
    }

    if (geometry.length < 2) {
      throw const FormatException('Edge geometry must include at least 2 coordinates');
    }

    return EdgeModel(
      from: from,
      to: to,
      type: normalizedType,
      geometry: geometry,
    );
  }
}
