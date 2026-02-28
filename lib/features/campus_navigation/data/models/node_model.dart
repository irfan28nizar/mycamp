class NodeModel {
  const NodeModel({
    required this.id,
    required this.lat,
    required this.lng,
  });

  final int id;
  final double lat;
  final double lng;

  factory NodeModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final lat = json['lat'];
    final lng = json['lng'];

    if (id is! int || lat is! num || lng is! num) {
      throw const FormatException('Invalid NodeModel JSON payload');
    }

    return NodeModel(
      id: id,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
    );
  }
}
