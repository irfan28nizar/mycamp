class PlaceModel {
  const PlaceModel({
    required this.id,
    required this.name,
    required this.nodeId,
  });

  final String id;
  final String name;
  final int nodeId;

  factory PlaceModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final nodeId = json['node_id'];

    if (id is! String || name is! String || nodeId is! int) {
      throw const FormatException('Invalid PlaceModel JSON payload');
    }

    return PlaceModel(
      id: id,
      name: name,
      nodeId: nodeId,
    );
  }
}
