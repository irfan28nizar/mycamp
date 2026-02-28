import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:mycamp_app/features/auth/data/repositories/hive_auth_repository.dart';
import 'package:mycamp_app/features/auth/presentation/screens/login_screen.dart';
import 'package:mycamp_app/features/admin/presentation/screens/admin_screen.dart';
import 'package:mycamp_app/features/campus_navigation/data/models/edge_model.dart';
import 'package:mycamp_app/features/campus_navigation/data/models/place_model.dart';
import 'package:mycamp_app/features/campus_navigation/data/services/navigation_data_service.dart';
import 'package:mycamp_app/features/campus_navigation/domain/services/graph_service.dart';
import 'package:mycamp_app/features/campus_navigation/presentation/utils/coordinate_mapper.dart';

class CampusNavigationScreen extends StatefulWidget {
  const CampusNavigationScreen({super.key});

  @override
  State<CampusNavigationScreen> createState() => _CampusNavigationScreenState();
}

class _CampusNavigationScreenState extends State<CampusNavigationScreen> {
  static const double _projectionEpsilon = 0.01;
  final HiveAuthRepository _authRepository = HiveAuthRepository();
  late final Future<String?> _currentUserRoleFuture;
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final NavigationDataService _navigationDataService = NavigationDataService();
  final CoordinateMapper _coordinateMapper = const CoordinateMapper(
    width: 4000,
    height: 2828,
    north: 8.996,
    south: 8.992,
    east: 76.699,
    west: 76.693,
    // Same calibration used in HomeMapScreen.
    affineXLng: 729656.4277369522,
    affineXLat: -8676.599459754943,
    affineXConst: -55881639.76519613,
    affineYLng: 532.8576296795654,
    affineYLat: -720765.6436928966,
    affineYConst: 6443383.548608216,
  );

  GraphService? _graphService;
  List<PlaceModel> _places = const <PlaceModel>[];
  List<EdgeModel> _edges = const <EdgeModel>[];
  Map<String, int> _placeNameToNodeId = const <String, int>{};
  List<Offset> _routePixels = const <Offset>[];
  List<PlaceModel> _startSuggestions = const <PlaceModel>[];
  List<PlaceModel> _destinationSuggestions = const <PlaceModel>[];
  int? _selectedStartNodeId;
  int? _selectedDestinationNodeId;
  bool _isSelectingStart = true;
  String? _lastScaleLogKey;

  @override
  void initState() {
    super.initState();
    _currentUserRoleFuture = _loadCurrentUserRole();
    _initializeNavigation();
  }

  @override
  void dispose() {
    _startController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<String?> _loadCurrentUserRole() async {
    final user = await _authRepository.getCurrentUser();
    return user?.role;
  }

  Future<void> _handleLogout() async {
    await _authRepository.logout();

    if (!mounted) {
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  Future<void> _initializeNavigation() async {
    await _navigationDataService.initialize();
    if (!mounted) {
      return;
    }

    final nodes = _navigationDataService.nodes;
    final places = _navigationDataService.places;
    final edges = _navigationDataService.edges;

    setState(() {
      _graphService = GraphService(nodes, edges);
      _places = places;
      _edges = edges;
      _placeNameToNodeId = {
        for (final place in places) place.name.toLowerCase(): place.nodeId,
      };
    });
    debugPrint('Loaded places count: ${_places.length}');
  }

  List<PlaceModel> _filterPlaces(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return _places.take(8).toList(growable: false);
    }
    return _places
        .where((place) => place.name.toLowerCase().contains(normalized))
        .take(6)
        .toList(growable: false);
  }

  void _onStartChanged(String value) {
    final normalized = value.trim().toLowerCase();
    setState(() {
      _selectedStartNodeId = _placeNameToNodeId[normalized];
      _startSuggestions = _filterPlaces(value);
      _isSelectingStart = true;
    });
  }

  void _onDestinationChanged(String value) {
    final normalized = value.trim().toLowerCase();
    setState(() {
      _selectedDestinationNodeId = _placeNameToNodeId[normalized];
      _destinationSuggestions = _filterPlaces(value);
      _isSelectingStart = false;
    });
  }

  void _onSuggestionTap({
    required PlaceModel place,
    required bool isStart,
  }) {
    setState(() {
      if (isStart) {
        _startController.text = place.name;
        _selectedStartNodeId = place.nodeId;
        _startSuggestions = const <PlaceModel>[];
      } else {
        _destinationController.text = place.name;
        _selectedDestinationNodeId = place.nodeId;
        _destinationSuggestions = const <PlaceModel>[];
      }
      _isSelectingStart = isStart;
    });
  }

  Future<void> _handleStartPressed() async {
    final startName = _startController.text.trim();
    final destinationName = _destinationController.text.trim();

    final startId =
        _selectedStartNodeId ?? _placeNameToNodeId[startName.toLowerCase()];
    final destinationId = _selectedDestinationNodeId ??
        _placeNameToNodeId[destinationName.toLowerCase()];

    debugPrint('START: name="$startName", nodeId=$startId');
    debugPrint('END: name="$destinationName", nodeId=$destinationId');

    if (startId == null || destinationId == null || _graphService == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select valid start and destination.')),
      );
      return;
    }

    final pathNodeIds = _graphService!.findShortestPath(
      startId,
      destinationId,
      'walk',
    );
    debugPrint('PATH NODE IDS: $pathNodeIds');

    if (pathNodeIds.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No route found between selected places.')),
      );
      return;
    }

    final routeBuild = _buildRoutePixelsFromEdgeGeometry(pathNodeIds);
    if (routeBuild.pixels.length < 2) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route geometry missing in edges data for this path.'),
        ),
      );
      setState(() {
        _routePixels = const <Offset>[];
      });
      return;
    }

    _logProjectionValidation(routeBuild);

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedStartNodeId = startId;
      _selectedDestinationNodeId = destinationId;
      _startSuggestions = const <PlaceModel>[];
      _destinationSuggestions = const <PlaceModel>[];
      _routePixels = routeBuild.pixels;
    });
    _lastScaleLogKey = null;
    debugPrint('Route rendered using edge geometry.');
  }

  _RouteBuildResult _buildRoutePixelsFromEdgeGeometry(List<int> nodePath) {
    final merged = <Offset>[];
    double? firstLat;
    double? firstLng;
    Offset? firstPixel;

    for (var i = 0; i < nodePath.length - 1; i++) {
      final fromId = nodePath[i];
      final toId = nodePath[i + 1];
      final segment = _segmentPixelsForPair(fromId, toId);
      if (segment == null || segment.pixels.isEmpty) {
        return const _RouteBuildResult(pixels: <Offset>[]);
      }

      if (firstLat == null &&
          firstLng == null &&
          segment.latLngPoints.isNotEmpty &&
          segment.pixels.isNotEmpty) {
        firstLat = segment.latLngPoints.first.latitude;
        firstLng = segment.latLngPoints.first.longitude;
        firstPixel = segment.pixels.first;
      }

      for (final point in segment.pixels) {
        if (merged.isEmpty || !_isSameOffset(merged.last, point)) {
          merged.add(point);
        }
      }
    }

    return _RouteBuildResult(
      pixels: merged,
      firstRouteLat: firstLat,
      firstRouteLng: firstLng,
      firstRoutePixel: firstPixel,
    );
  }

  _RouteSegmentResult? _segmentPixelsForPair(int fromId, int toId) {
    final edge = _findEdgeForPair(fromId, toId);
    if (edge == null || edge.geometry.isEmpty) {
      debugPrint('Missing geometry for edge $fromId-$toId');
      return null;
    }

    final isForward = edge.from == fromId && edge.to == toId;
    final points =
        (isForward ? edge.geometry : edge.geometry.reversed).toList(growable: false);
    final pixels = points
        .map((point) => _coordinateMapper.latLngToPixel(point.latitude, point.longitude))
        .toList(growable: false);

    return _RouteSegmentResult(
      latLngPoints: points,
      pixels: pixels,
    );
  }

  EdgeModel? _findEdgeForPair(int fromId, int toId) {
    for (final edge in _edges) {
      final isForward = edge.from == fromId && edge.to == toId;
      final isReverse = edge.from == toId && edge.to == fromId;
      if (isForward || isReverse) {
        return edge;
      }
    }
    return null;
  }

  bool _isSameOffset(Offset a, Offset b) {
    const epsilon = 0.0001;
    return (a.dx - b.dx).abs() < epsilon && (a.dy - b.dy).abs() < epsilon;
  }

  void _logProjectionValidation(_RouteBuildResult routeBuild) {
    final northWestPixel =
        _coordinateMapper.latLngToPixel(_coordinateMapper.north, _coordinateMapper.west);
    final southEastPixel =
        _coordinateMapper.latLngToPixel(_coordinateMapper.south, _coordinateMapper.east);

    final matchesTopLeft = northWestPixel.dx.abs() < _projectionEpsilon &&
        northWestPixel.dy.abs() < _projectionEpsilon;
    final matchesBottomRight =
        (southEastPixel.dx - _coordinateMapper.width).abs() < _projectionEpsilon &&
            (southEastPixel.dy - _coordinateMapper.height).abs() < _projectionEpsilon;

    debugPrint(
      'Map bounds: N=${_coordinateMapper.north}, S=${_coordinateMapper.south}, '
      'E=${_coordinateMapper.east}, W=${_coordinateMapper.west}, '
      'image=${_coordinateMapper.width}x${_coordinateMapper.height}',
    );
    if (routeBuild.firstRouteLat != null &&
        routeBuild.firstRouteLng != null &&
        routeBuild.firstRoutePixel != null) {
      debugPrint(
        'First route LatLng: (${routeBuild.firstRouteLat}, ${routeBuild.firstRouteLng})',
      );
      debugPrint('Converted pixel: ${routeBuild.firstRoutePixel}');
    }

    if (matchesTopLeft && matchesBottomRight) {
      debugPrint('Projection validation passed.');
      return;
    }

    debugPrint(
      'Projection mismatch detected: topLeft=$northWestPixel, bottomRight=$southEastPixel',
    );
  }

  Widget _buildSuggestions({
    required List<PlaceModel> suggestions,
    required bool isStart,
  }) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: const BoxConstraints(maxHeight: 180),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: suggestions.length,
        separatorBuilder: (_, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final place = suggestions[index];
          return ListTile(
            dense: true,
            title: Text(place.name),
            onTap: () => _onSuggestionTap(place: place, isStart: isStart),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0E8F9A);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: teal,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: FutureBuilder<String?>(
                        future: _currentUserRoleFuture,
                        builder: (context, snapshot) {
                          final isStudent = snapshot.data == 'student';
                          final isAdmin = snapshot.data == 'admin';
                          if (!isStudent && !isAdmin) {
                            return const SizedBox(width: 48, height: 48);
                          }

                          return PopupMenuButton<String>(
                            tooltip: 'Menu',
                            icon: const Icon(Icons.more_vert, color: Colors.white),
                            onSelected: (value) {
                              if (value == 'admin_panel') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AdminScreen(),
                                  ),
                                );
                                return;
                              }

                              if (value == 'logout') {
                                _handleLogout();
                              }
                            },
                            itemBuilder: (_) => [
                              if (isAdmin)
                                const PopupMenuItem<String>(
                                  value: 'admin_panel',
                                  child: Text('Admin Panel'),
                                ),
                              const PopupMenuItem<String>(
                                value: 'logout',
                                child: Text('Logout'),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    _SearchField(
                      hintText: 'starting point...',
                      controller: _startController,
                      isActive: _isSelectingStart,
                      onTap: () {
                        setState(() {
                          _isSelectingStart = true;
                          _startSuggestions = _filterPlaces(_startController.text);
                        });
                      },
                      onChanged: _onStartChanged,
                    ),
                    if (_isSelectingStart)
                      _buildSuggestions(
                        suggestions: _startSuggestions,
                        isStart: true,
                      ),
                    const SizedBox(height: 10),
                    _SearchField(
                      hintText: 'where to...',
                      controller: _destinationController,
                      isActive: !_isSelectingStart,
                      onTap: () {
                        setState(() {
                          _isSelectingStart = false;
                          _destinationSuggestions =
                              _filterPlaces(_destinationController.text);
                        });
                      },
                      onChanged: _onDestinationChanged,
                    ),
                    if (!_isSelectingStart)
                      _buildSuggestions(
                        suggestions: _destinationSuggestions,
                        isStart: false,
                      ),
                    const SizedBox(height: 14),
                    Align(
                      child: SizedBox(
                        height: 36,
                        child: ElevatedButton(
                          onPressed: _handleStartPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: teal,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          child: const Text(
                            'GO >>',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  final maxH = constraints.maxHeight;
                  final imageAspect = _coordinateMapper.width / _coordinateMapper.height;
                  late final double mapW;
                  late final double mapH;

                  if ((maxW / maxH) > imageAspect) {
                    mapH = maxH;
                    mapW = mapH * imageAspect;
                  } else {
                    mapW = maxW;
                    mapH = mapW / imageAspect;
                  }

                  final scaleX = mapW / _coordinateMapper.width;
                  final scaleY = mapH / _coordinateMapper.height;
                  final scaleLogKey = '${scaleX.toStringAsFixed(6)}:${scaleY.toStringAsFixed(6)}';
                  if (_routePixels.length >= 2 && _lastScaleLogKey != scaleLogKey) {
                    _lastScaleLogKey = scaleLogKey;
                    debugPrint('Calculated scaling ratios: scaleX=$scaleX, scaleY=$scaleY');
                    if ((scaleX - scaleY).abs() <= 0.000001) {
                      debugPrint(
                        'Route polyline aligns with campus_map.png overlay using identical aspect scaling.',
                      );
                    }
                  }

                  final left = (maxW - mapW) / 2;
                  final top = (maxH - mapH) / 2;

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Container(color: const Color(0xFFE5E5E5)),
                      ),
                      Positioned(
                        left: left,
                        top: top,
                        width: mapW,
                        height: mapH,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              'assets/maps/campus_map.png',
                              fit: BoxFit.contain,
                            ),
                            CustomPaint(
                              painter: RoutePainter(
                                routePixels: _routePixels,
                                sourceWidth: _coordinateMapper.width,
                                sourceHeight: _coordinateMapper.height,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteSegmentResult {
  const _RouteSegmentResult({
    required this.latLngPoints,
    required this.pixels,
  });

  final List<ll.LatLng> latLngPoints;
  final List<Offset> pixels;
}

class _RouteBuildResult {
  const _RouteBuildResult({
    required this.pixels,
    this.firstRouteLat,
    this.firstRouteLng,
    this.firstRoutePixel,
  });

  final List<Offset> pixels;
  final double? firstRouteLat;
  final double? firstRouteLng;
  final Offset? firstRoutePixel;
}

class RoutePainter extends CustomPainter {
  RoutePainter({
    required this.routePixels,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final List<Offset> routePixels;
  final double sourceWidth;
  final double sourceHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (routePixels.length < 2) {
      return;
    }

    final scaleX = size.width / sourceWidth;
    final scaleY = size.height / sourceHeight;
    final path =
        Path()..moveTo(routePixels.first.dx * scaleX, routePixels.first.dy * scaleY);

    for (final point in routePixels.skip(1)) {
      path.lineTo(point.dx * scaleX, point.dy * scaleY);
    }

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant RoutePainter oldDelegate) {
    return oldDelegate.routePixels != routePixels;
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.hintText,
    required this.controller,
    required this.isActive,
    required this.onTap,
    required this.onChanged,
  });

  final String hintText;
  final TextEditingController controller;
  final bool isActive;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onTap: onTap,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: isActive ? Colors.white : const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }
}
