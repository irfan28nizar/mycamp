import 'dart:ui';

class CoordinateMapper {
  final double width;
  final double height;
  final double north;
  final double south;
  final double east;
  final double west;
  final double? affineXLng;
  final double? affineXLat;
  final double? affineXConst;
  final double? affineYLng;
  final double? affineYLat;
  final double? affineYConst;

  const CoordinateMapper({
    required this.width,
    required this.height,
    required this.north,
    required this.south,
    required this.east,
    required this.west,
    this.affineXLng,
    this.affineXLat,
    this.affineXConst,
    this.affineYLng,
    this.affineYLat,
    this.affineYConst,
  });

  Offset latLngToPixel(double lat, double lng) {
    if (affineXLng != null &&
        affineXLat != null &&
        affineXConst != null &&
        affineYLng != null &&
        affineYLat != null &&
        affineYConst != null) {
      final x = (affineXLng! * lng) + (affineXLat! * lat) + affineXConst!;
      final y = (affineYLng! * lng) + (affineYLat! * lat) + affineYConst!;
      return Offset(x, y);
    }

    final x = ((lng - west) / (east - west)) * width;
    final y = ((north - lat) / (north - south)) * height;

    return Offset(x, y);
  }
}
