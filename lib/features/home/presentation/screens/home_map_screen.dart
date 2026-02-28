import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mycamp_app/features/campus_navigation/data/models/edge_model.dart';
import 'package:mycamp_app/features/campus_navigation/data/models/node_model.dart';
import 'package:mycamp_app/features/campus_navigation/data/models/place_model.dart';
import 'package:mycamp_app/features/campus_navigation/data/services/navigation_data_service.dart';
import 'package:mycamp_app/features/campus_navigation/domain/services/graph_service.dart';
import 'package:mycamp_app/features/campus_navigation/presentation/utils/coordinate_mapper.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen>
    with SingleTickerProviderStateMixin {
  static const double _minMapScale = 0.05;
  static const double _maxMapScale = 30.0;
  static const double _zoomStep = 1.25;
  static const String _currentLocationLabel = 'Current location';
  static const Color _primaryTeal = Color(0xFF1DA0AA);
  static const Color _primaryTealDark = Color(0xFF0B5B66);

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
    // Calibrated from node-to-pixel anchors shared in debugging:
    // n2(1723,2116), n3(1834,1859), n4(1918,1256), n15(2296,804).
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
  Map<int, NodeModel> _nodesById = const <int, NodeModel>{};
  Map<String, int> _placeNameToNodeId = const <String, int>{};
  List<PlaceModel> _startSuggestions = const <PlaceModel>[];
  List<PlaceModel> _destinationSuggestions = const <PlaceModel>[];
  List<Offset> _routePixels = const <Offset>[];
  List<int> _activePathNodeIds = const <int>[];
  List<_RouteInstruction> _routeInstructions = const <_RouteInstruction>[];
  List<_TurnPoint> _turnPoints = const <_TurnPoint>[];
  int _nextInstructionIndex = 0;
  double? _distanceToNextMeters;
  double? _distanceToDestinationMeters;
  Offset? _currentLocationPixel;
  int? _selectedStartNodeId;
  int? _selectedDestinationNodeId;
  bool _useCurrentLocationAsStart = true;
  bool _isSelectingStart = true;
  String _travelMode = 'walk';
  StreamSubscription<Position>? _positionSubscription;
  Position? _latestPosition;
  double? _currentHeadingDegrees;
  bool _followMeEnabled = true;
  DateTime _lastFollowCameraUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  late final TransformationController _mapTransformationController;
  late final AnimationController _mapAnimationController;
  Animation<Matrix4>? _mapMatrixAnimation;
  Size? _mapViewportSize;
  bool _hasLoggedMapRenderSize = false;

  @override
  void initState() {
    super.initState();
    _mapTransformationController = TransformationController();
    _mapAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(() {
        final animation = _mapMatrixAnimation;
        if (animation != null) {
          _mapTransformationController.value = animation.value;
        }
      });
    _startController.text = _currentLocationLabel;
    _initializeNavigation();
    _initializeLocationTracking();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapAnimationController.dispose();
    _mapTransformationController.dispose();
    _startController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _initializeLocationTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location service is disabled.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('Location permission denied.');
      return;
    }

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      _onLivePosition(current);
    } catch (_) {
      debugPrint('Unable to fetch current location.');
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen(
      _onLivePosition,
      onError: (Object error) {
        debugPrint('Location stream error: $error');
      },
    );
  }

  void _onLivePosition(Position position) {
    _latestPosition = position;
    final hasHeading = position.heading.isFinite && position.heading >= 0;
    _currentHeadingDegrees = hasHeading ? position.heading : null;
    final rawPixel =
        _coordinateMapper.latLngToPixel(position.latitude, position.longitude);
    final snappedPixel = _routePixels.length >= 2
        ? _snapPointToRoute(rawPixel, _routePixels)
        : rawPixel;

    if (!mounted) {
      return;
    }
    setState(() {
      _currentLocationPixel = snappedPixel;
    });
    _updateNavigationProgress(
      latitude: position.latitude,
      longitude: position.longitude,
    );

    if (_followMeEnabled) {
      final now = DateTime.now();
      if (now.difference(_lastFollowCameraUpdate).inMilliseconds >= 700) {
        _lastFollowCameraUpdate = now;
        _centerOnPixel(snappedPixel);
      }
    }
    debugPrint(
      'Live location: (${position.latitude}, ${position.longitude}) -> '
      'pixel (${snappedPixel.dx}, ${snappedPixel.dy})',
    );
  }

  Future<void> _initializeNavigation() async {
    await _navigationDataService.initialize();
    if (!mounted) {
      return;
    }

    final places = _navigationDataService.places;
    final nodes = _navigationDataService.nodes;
    final edges = _navigationDataService.edges;
    setState(() {
      _graphService = GraphService(
        nodes,
        edges,
      );
      _places = places;
      _edges = edges;
      _nodesById = {for (final node in nodes) node.id: node};
      _placeNameToNodeId = {
        for (final place in places) place.name.toLowerCase(): place.nodeId,
      };
    });
  }

  List<PlaceModel> _filterPlaces(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return _places.take(8).toList(growable: false);
    }
    return _places
        .where((place) => place.name.toLowerCase().contains(normalized))
        .take(8)
        .toList(growable: false);
  }

  void _onStartChanged(String value) {
    final normalized = value.trim().toLowerCase();
    final isCurrentLocation =
        normalized == _currentLocationLabel.toLowerCase() || normalized.isEmpty;
    setState(() {
      _selectedStartNodeId = _placeNameToNodeId[normalized];
      _useCurrentLocationAsStart = isCurrentLocation;
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
        _useCurrentLocationAsStart = false;
        _startSuggestions = const <PlaceModel>[];
      } else {
        _destinationController.text = place.name;
        _selectedDestinationNodeId = place.nodeId;
        _destinationSuggestions = const <PlaceModel>[];
      }
      _isSelectingStart = isStart;
    });
  }

  void _onCurrentLocationStartTap() {
    setState(() {
      _startController.text = _currentLocationLabel;
      _selectedStartNodeId = null;
      _useCurrentLocationAsStart = true;
      _startSuggestions = const <PlaceModel>[];
      _isSelectingStart = true;
    });
  }

  Future<void> _handleStartPressed() async {
    final startName = _startController.text.trim();
    final destinationName = _destinationController.text.trim();

    final typedStartId = _placeNameToNodeId[startName.toLowerCase()];
    var startId = _useCurrentLocationAsStart ? null : _selectedStartNodeId ?? typedStartId;
    final destinationId = _selectedDestinationNodeId ??
        _placeNameToNodeId[destinationName.toLowerCase()];
    if (_useCurrentLocationAsStart && _latestPosition != null) {
      startId = _nearestNodeIdForLatLng(
        _latestPosition!.latitude,
        _latestPosition!.longitude,
      );
    }

    debugPrint('START: name="$startName", nodeId=$startId');
    debugPrint('END: name="$destinationName", nodeId=$destinationId');

    if (_graphService == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Navigation data is still loading. Try again.')),
      );
      return;
    }

    if (destinationId == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a valid destination.')),
      );
      return;
    }

    if (startId == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable location or select a valid starting point.'),
        ),
      );
      return;
    }

    final pathNodeIds = _graphService!.findShortestPath(
      startId,
      destinationId,
      _travelMode,
    );
    debugPrint('PATH NODE IDS: $pathNodeIds');

    if (pathNodeIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No route found.')),
        );
      }
      setState(() {
        _routePixels = const <Offset>[];
        _activePathNodeIds = const <int>[];
        _routeInstructions = const <_RouteInstruction>[];
        _turnPoints = const <_TurnPoint>[];
        _nextInstructionIndex = 0;
        _distanceToNextMeters = null;
        _distanceToDestinationMeters = null;
        _currentLocationPixel = _latestPosition == null
            ? null
            : _coordinateMapper.latLngToPixel(
                _latestPosition!.latitude,
                _latestPosition!.longitude,
              );
      });
      return;
    }

    final routePixels = _buildRoutePixelsFromEdgeGeometry(pathNodeIds);
    if (routePixels.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Route geometry missing in edges data for this path.'),
          ),
        );
      }
      setState(() {
        _routePixels = const <Offset>[];
        _activePathNodeIds = const <int>[];
        _routeInstructions = const <_RouteInstruction>[];
        _turnPoints = const <_TurnPoint>[];
        _nextInstructionIndex = 0;
        _distanceToNextMeters = null;
        _distanceToDestinationMeters = null;
        _currentLocationPixel = _latestPosition == null
            ? null
            : _coordinateMapper.latLngToPixel(
                _latestPosition!.latitude,
                _latestPosition!.longitude,
              );
      });
      return;
    }

    final instructionBuild = _buildInstructions(pathNodeIds);
    final rawCurrent = _latestPosition == null
        ? (_pixelForNode(startId) ?? routePixels.first)
        : _coordinateMapper.latLngToPixel(
            _latestPosition!.latitude,
            _latestPosition!.longitude,
          );
    final currentLocation = _snapPointToRoute(rawCurrent, routePixels);

    setState(() {
      _startSuggestions = const <PlaceModel>[];
      _destinationSuggestions = const <PlaceModel>[];
      _routePixels = routePixels;
      _activePathNodeIds = pathNodeIds;
      _routeInstructions = instructionBuild.instructions;
      _turnPoints = instructionBuild.turnPoints;
      _nextInstructionIndex = 0;
      _distanceToNextMeters = null;
      _distanceToDestinationMeters = null;
      _currentLocationPixel = currentLocation;
      _selectedStartNodeId = startId;
      if (_useCurrentLocationAsStart) {
        _startController.text = _currentLocationLabel;
      }
    });

    final progressNode = _latestPosition == null ? _nodesById[startId] : null;
    if (_latestPosition != null) {
      _updateNavigationProgress(
        latitude: _latestPosition!.latitude,
        longitude: _latestPosition!.longitude,
      );
    } else if (progressNode != null) {
      _updateNavigationProgress(
        latitude: progressNode.lat,
        longitude: progressNode.lng,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _fitToRoute(routePixels);
    });
    debugPrint('Route rendered using edge geometry.');
  }

  List<Offset> _buildRoutePixelsFromEdgeGeometry(List<int> nodePath) {
    final merged = <Offset>[];

    for (var i = 0; i < nodePath.length - 1; i++) {
      final fromId = nodePath[i];
      final toId = nodePath[i + 1];
      final segment = _segmentPixelsForPair(fromId, toId);
      if (segment.isEmpty) {
        return const <Offset>[];
      }

      for (final point in segment) {
        if (merged.isEmpty || !_isSameOffset(merged.last, point)) {
          merged.add(point);
        }
      }
    }

    return merged;
  }

  List<Offset> _segmentPixelsForPair(int fromId, int toId) {
    final edge = _findEdgeForPair(fromId, toId);
    if (edge == null || edge.geometry.isEmpty) {
      debugPrint('Missing geometry for edge $fromId-$toId');
      return const <Offset>[];
    }

    final isForward = edge.from == fromId && edge.to == toId;
    final points = isForward ? edge.geometry : edge.geometry.reversed;

    return points
        .map(
          (point) => _coordinateMapper.latLngToPixel(
            point.latitude,
            point.longitude,
          ),
        )
        .toList(growable: false);
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

  void _onMapViewportChanged(Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return;
    }

    if (_mapViewportSize == viewportSize) {
      return;
    }
    _mapViewportSize = viewportSize;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_routePixels.length >= 2) {
        _fitToRoute(_routePixels, animated: false);
      } else {
        _fitWholeMap(animated: false);
      }
    });
  }

  void _fitWholeMap({bool animated = true}) {
    final viewport = _mapViewportSize;
    if (viewport == null) {
      return;
    }

    final scale = math.min(
      viewport.width / _coordinateMapper.width,
      viewport.height / _coordinateMapper.height,
    );
    final translateX = (viewport.width - (_coordinateMapper.width * scale)) / 2;
    final translateY = (viewport.height - (_coordinateMapper.height * scale)) / 2;

    final matrix = Matrix4.identity()
      ..translateByDouble(translateX, translateY, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    _animateToMatrix(matrix, animated: animated);
  }

  void _fitToRoute(List<Offset> routePixels, {bool animated = true}) {
    final viewport = _mapViewportSize;
    if (viewport == null || routePixels.length < 2) {
      return;
    }

    double minX = routePixels.first.dx;
    double maxX = routePixels.first.dx;
    double minY = routePixels.first.dy;
    double maxY = routePixels.first.dy;

    for (final point in routePixels.skip(1)) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }

    final routeWidth = math.max(maxX - minX, 1.0);
    final routeHeight = math.max(maxY - minY, 1.0);
    final paddedWidth = routeWidth * 1.2;
    final paddedHeight = routeHeight * 1.2;
    final computedScale = math.min(
      viewport.width / paddedWidth,
      viewport.height / paddedHeight,
    );
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    debugPrint('routeWidth: $routeWidth');
    debugPrint('routeHeight: $routeHeight');
    debugPrint('computedScale: $computedScale');
    debugPrint('centerX, centerY: $centerX, $centerY');

    final matrix = Matrix4.identity()
      ..translateByDouble(
        (viewport.width / 2) - (centerX * computedScale),
        (viewport.height / 2) - (centerY * computedScale),
        0,
        1,
      )
      ..scaleByDouble(computedScale, computedScale, 1, 1);

    _animateToMatrix(matrix, animated: animated);
  }

  void _animateToMatrix(Matrix4 target, {bool animated = true}) {
    if (!animated) {
      _mapAnimationController.stop();
      _mapTransformationController.value = target;
      return;
    }

    _mapAnimationController.stop();
    final begin = Matrix4.copy(_mapTransformationController.value);
    _mapMatrixAnimation = Matrix4Tween(begin: begin, end: target).animate(
      CurvedAnimation(
        parent: _mapAnimationController,
        curve: Curves.easeInOutCubic,
      ),
    );
    _mapAnimationController.forward(from: 0);
  }

  void _zoomMap({required bool zoomIn}) {
    final viewport = _mapViewportSize;
    if (viewport == null) {
      return;
    }

    final currentScale = _mapTransformationController.value.getMaxScaleOnAxis();
    if (currentScale <= 0) {
      return;
    }

    final targetScale = (zoomIn ? currentScale * _zoomStep : currentScale / _zoomStep)
        .clamp(_minMapScale, _maxMapScale);
    if ((targetScale - currentScale).abs() < 0.000001) {
      return;
    }

    final viewportCenter = Offset(viewport.width / 2, viewport.height / 2);
    final sceneCenter = _mapTransformationController.toScene(viewportCenter);
    final targetTx = viewportCenter.dx - (sceneCenter.dx * targetScale);
    final targetTy = viewportCenter.dy - (sceneCenter.dy * targetScale);

    final targetMatrix = Matrix4.identity()
      ..translateByDouble(targetTx, targetTy, 0, 1)
      ..scaleByDouble(targetScale, targetScale, 1, 1);

    if (_followMeEnabled) {
      setState(() {
        _followMeEnabled = false;
      });
    }
    _animateToMatrix(targetMatrix);
  }

  void _centerOnPixel(Offset pixel, {bool animated = true}) {
    final viewport = _mapViewportSize;
    if (viewport == null) {
      return;
    }

    final currentScale = _mapTransformationController.value.getMaxScaleOnAxis();
    final scale = currentScale > 0 ? currentScale : 1.0;
    final matrix = Matrix4.identity()
      ..translateByDouble(
        (viewport.width / 2) - (pixel.dx * scale),
        (viewport.height / 2) - (pixel.dy * scale),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
    _animateToMatrix(matrix, animated: animated);
  }

  Offset? _pixelForNode(int nodeId) {
    final node = _nodesById[nodeId];
    if (node == null) {
      return null;
    }
    return _coordinateMapper.latLngToPixel(node.lat, node.lng);
  }

  Offset _snapPointToRoute(Offset point, List<Offset> route) {
    if (route.isEmpty) {
      return point;
    }
    if (route.length == 1) {
      return route.first;
    }

    var bestPoint = route.first;
    var bestDistance = double.infinity;
    for (var i = 0; i < route.length - 1; i++) {
      final projected = _nearestPointOnSegment(point, route[i], route[i + 1]);
      final distance = (projected - point).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPoint = projected;
      }
    }
    return bestPoint;
  }

  int? _nearestNodeIdForLatLng(double latitude, double longitude) {
    if (_nodesById.isEmpty) {
      return null;
    }

    int? nearestNodeId;
    var nearestDistance = double.infinity;
    for (final node in _nodesById.values) {
      final distance = _haversineMeters(latitude, longitude, node.lat, node.lng);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestNodeId = node.id;
      }
    }
    return nearestNodeId;
  }

  Offset _nearestPointOnSegment(Offset p, Offset a, Offset b) {
    final abX = b.dx - a.dx;
    final abY = b.dy - a.dy;
    final abLengthSquared = (abX * abX) + (abY * abY);
    if (abLengthSquared <= 0.000001) {
      return a;
    }
    final apX = p.dx - a.dx;
    final apY = p.dy - a.dy;
    final t = ((apX * abX) + (apY * abY)) / abLengthSquared;
    final clampedT = t.clamp(0.0, 1.0);
    return Offset(a.dx + (abX * clampedT), a.dy + (abY * clampedT));
  }

  _InstructionBuildResult _buildInstructions(List<int> pathNodeIds) {
    if (pathNodeIds.length < 2) {
      return const _InstructionBuildResult(
        instructions: <_RouteInstruction>[],
        turnPoints: <_TurnPoint>[],
      );
    }

    final instructions = <_RouteInstruction>[];
    final turnPoints = <_TurnPoint>[];
    var accumulatedDistance = 0.0;

    for (var i = 0; i < pathNodeIds.length - 1; i++) {
      final fromNode = _nodesById[pathNodeIds[i]];
      final toNode = _nodesById[pathNodeIds[i + 1]];
      if (fromNode == null || toNode == null) {
        continue;
      }

      accumulatedDistance += _haversineMeters(
        fromNode.lat,
        fromNode.lng,
        toNode.lat,
        toNode.lng,
      );

      if (i == 0 || i == pathNodeIds.length - 2) {
        continue;
      }

      final prevNode = _nodesById[pathNodeIds[i - 1]];
      final currentNode = _nodesById[pathNodeIds[i]];
      final nextNode = _nodesById[pathNodeIds[i + 1]];
      if (prevNode == null || currentNode == null || nextNode == null) {
        continue;
      }

      final bearingIn = _bearingDegrees(
        prevNode.lat,
        prevNode.lng,
        currentNode.lat,
        currentNode.lng,
      );
      final bearingOut = _bearingDegrees(
        currentNode.lat,
        currentNode.lng,
        nextNode.lat,
        nextNode.lng,
      );
      final delta = _normalizeBearingDelta(bearingOut - bearingIn);
      final turn = _turnForDelta(delta);

      if (turn == null) {
        continue;
      }

      final instruction = _RouteInstruction(
        icon: turn.icon,
        text: turn.label,
        distanceText: _formatDistance(accumulatedDistance),
      );
      instructions.add(instruction);
      turnPoints.add(
        _TurnPoint(
          instructionIndex: instructions.length - 1,
          pathNodeIndex: i,
        ),
      );
      accumulatedDistance = 0.0;
    }

    if (instructions.isEmpty) {
      instructions.add(
        _RouteInstruction(
          icon: Icons.straight,
          text: 'Continue to destination',
          distanceText: '',
        ),
      );
    }

    instructions.add(
      _RouteInstruction(
        icon: Icons.flag,
        text: 'Arrive at destination',
        distanceText: _formatDistance(accumulatedDistance),
      ),
    );
    turnPoints.add(
      _TurnPoint(
        instructionIndex: instructions.length - 1,
        pathNodeIndex: pathNodeIds.length - 1,
      ),
    );

    return _InstructionBuildResult(
      instructions: instructions,
      turnPoints: turnPoints,
    );
  }

  void _updateNavigationProgress({
    required double latitude,
    required double longitude,
  }) {
    if (_activePathNodeIds.length < 2 || _turnPoints.isEmpty) {
      return;
    }

    var nearestPathIndex = 0;
    var nearestDistance = double.infinity;
    for (var i = 0; i < _activePathNodeIds.length; i++) {
      final node = _nodesById[_activePathNodeIds[i]];
      if (node == null) {
        continue;
      }
      final distance = _haversineMeters(latitude, longitude, node.lat, node.lng);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestPathIndex = i;
      }
    }

    _TurnPoint nextTurn = _turnPoints.last;
    for (final turn in _turnPoints) {
      if (turn.pathNodeIndex >= nearestPathIndex) {
        nextTurn = turn;
        break;
      }
    }

    final distanceToNext = _distanceFromCurrentToPathIndex(
      latitude: latitude,
      longitude: longitude,
      nearestPathIndex: nearestPathIndex,
      targetPathIndex: nextTurn.pathNodeIndex,
    );
    final distanceToDestination = _distanceFromCurrentToPathIndex(
      latitude: latitude,
      longitude: longitude,
      nearestPathIndex: nearestPathIndex,
      targetPathIndex: _activePathNodeIds.length - 1,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _nextInstructionIndex = nextTurn.instructionIndex;
      _distanceToNextMeters = distanceToNext;
      _distanceToDestinationMeters = distanceToDestination;
    });
  }

  double _distanceFromCurrentToPathIndex({
    required double latitude,
    required double longitude,
    required int nearestPathIndex,
    required int targetPathIndex,
  }) {
    if (_activePathNodeIds.isEmpty) {
      return 0;
    }
    final safeNearest = nearestPathIndex.clamp(0, _activePathNodeIds.length - 1);
    final safeTarget = targetPathIndex.clamp(0, _activePathNodeIds.length - 1);
    final nearestNode = _nodesById[_activePathNodeIds[safeNearest]];
    if (nearestNode == null) {
      return 0;
    }

    if (safeTarget <= safeNearest) {
      final targetNode = _nodesById[_activePathNodeIds[safeTarget]];
      if (targetNode == null) {
        return 0;
      }
      return _haversineMeters(latitude, longitude, targetNode.lat, targetNode.lng);
    }

    var distance = _haversineMeters(latitude, longitude, nearestNode.lat, nearestNode.lng);
    for (var i = safeNearest; i < safeTarget; i++) {
      final from = _nodesById[_activePathNodeIds[i]];
      final to = _nodesById[_activePathNodeIds[i + 1]];
      if (from == null || to == null) {
        continue;
      }
      distance += _haversineMeters(from.lat, from.lng, to.lat, to.lng);
    }
    return distance;
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * (math.pi / 180.0);

  double _bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = _toRadians(lat1);
    final phi2 = _toRadians(lat2);
    final dLon = _toRadians(lon2 - lon1);
    final y = math.sin(dLon) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  double _normalizeBearingDelta(double delta) {
    var normalized = delta % 360;
    if (normalized > 180) {
      normalized -= 360;
    } else if (normalized < -180) {
      normalized += 360;
    }
    return normalized;
  }

  _TurnDescriptor? _turnForDelta(double delta) {
    final absDelta = delta.abs();
    if (absDelta < 20) {
      return null;
    }
    if (delta >= 20 && delta < 55) {
      return const _TurnDescriptor(Icons.turn_slight_right, 'Slight right');
    }
    if (delta <= -20 && delta > -55) {
      return const _TurnDescriptor(Icons.turn_slight_left, 'Slight left');
    }
    if (delta >= 55 && delta < 130) {
      return const _TurnDescriptor(Icons.turn_right, 'Turn right');
    }
    if (delta <= -55 && delta > -130) {
      return const _TurnDescriptor(Icons.turn_left, 'Turn left');
    }
    return delta > 0
        ? const _TurnDescriptor(Icons.u_turn_right, 'Make a U-turn')
        : const _TurnDescriptor(Icons.u_turn_left, 'Make a U-turn');
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  Widget _buildSuggestions({
    required List<PlaceModel> suggestions,
    required bool isStart,
  }) {
    final hasCurrentLocationOption = isStart;
    if (suggestions.isEmpty && !hasCurrentLocationOption) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x17000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 210),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: suggestions.length + (hasCurrentLocationOption ? 1 : 0),
        separatorBuilder: (_, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (hasCurrentLocationOption && index == 0) {
            return ListTile(
              dense: true,
              leading: const Icon(Icons.my_location, color: _primaryTealDark),
              title: const Text(
                _currentLocationLabel,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Use your live GPS position',
                style: TextStyle(fontSize: 12),
              ),
              onTap: _onCurrentLocationStartTap,
            );
          }

          final place = suggestions[index - (hasCurrentLocationOption ? 1 : 0)];
          return ListTile(
            dense: true,
            leading: Icon(
              isStart ? Icons.trip_origin : Icons.location_on_outlined,
              color: isStart ? const Color(0xFF1A8F97) : const Color(0xFF1967D2),
            ),
            title: Text(
              place.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => _onSuggestionTap(place: place, isStart: isStart),
          );
        },
      ),
    );
  }

  Widget _buildMapControlButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color iconColor = Colors.black87,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      shadowColor: const Color(0x22000000),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: iconColor),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topSectionHeight = (screenHeight * 0.40).clamp(300.0, 430.0);
    final startPixel = _selectedStartNodeId == null
        ? null
        : _pixelForNode(_selectedStartNodeId!);
    final destinationPixel = _selectedDestinationNodeId == null
        ? null
        : _pixelForNode(_selectedDestinationNodeId!);
    final hasLiveLocation = _latestPosition != null;

    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: topSectionHeight,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFF0A4F58),
                    Color(0xFF127583),
                    Color(0xFF3A9FA8),
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Home Navigation',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Choose where to go and start turn-by-turn guidance.',
                                style: TextStyle(
                                  color: Color(0xD9FFFFFF),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: hasLiveLocation
                                ? const Color(0x2DFFFFFF)
                                : const Color(0x25FDE68A),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: hasLiveLocation
                                  ? const Color(0x4CFFFFFF)
                                  : const Color(0x66FDE68A),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasLiveLocation
                                    ? Icons.gps_fixed_rounded
                                    : Icons.gps_off_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                hasLiveLocation ? 'Live' : 'No GPS',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xF8FFFFFF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0x59FFFFFF)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 16,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Column(
                        children: [
                          _SearchField(
                            hint: 'Starting point (current location by default)',
                            icon: Icons.location_on_outlined,
                            controller: _startController,
                            onTap: () {
                              setState(() {
                                _isSelectingStart = true;
                                _startSuggestions = _filterPlaces(
                                  _useCurrentLocationAsStart ? '' : _startController.text,
                                );
                              });
                            },
                            onChanged: _onStartChanged,
                          ),
                          if (_isSelectingStart)
                            _buildSuggestions(suggestions: _startSuggestions, isStart: true),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('Walk'),
                                  avatar: const Icon(Icons.directions_walk, size: 18),
                                  selected: _travelMode == 'walk',
                                  selectedColor: const Color(0xFFD2F2F1),
                                  side: BorderSide(
                                    color: _travelMode == 'walk'
                                        ? const Color(0xFF69BFC3)
                                        : const Color(0xFFD7E2EA),
                                  ),
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _travelMode == 'walk'
                                        ? _primaryTealDark
                                        : const Color(0xFF4A5560),
                                  ),
                                  onSelected: (_) {
                                    setState(() => _travelMode = 'walk');
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('Drive'),
                                  avatar: const Icon(Icons.directions_car, size: 18),
                                  selected: _travelMode == 'drive',
                                  selectedColor: const Color(0xFFDDE8FF),
                                  side: BorderSide(
                                    color: _travelMode == 'drive'
                                        ? const Color(0xFF9DB5F7)
                                        : const Color(0xFFD7E2EA),
                                  ),
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _travelMode == 'drive'
                                        ? const Color(0xFF1F4EAE)
                                        : const Color(0xFF4A5560),
                                  ),
                                  onSelected: (_) {
                                    setState(() => _travelMode = 'drive');
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _SearchField(
                                  hint: 'Your destination',
                                  icon: Icons.search,
                                  controller: _destinationController,
                                  onTap: () {
                                    setState(() {
                                      _isSelectingStart = false;
                                      _destinationSuggestions =
                                          _filterPlaces(_destinationController.text);
                                    });
                                  },
                                  onChanged: _onDestinationChanged,
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 56,
                                child: ElevatedButton.icon(
                                  onPressed: _handleStartPressed,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primaryTeal,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                  ),
                                  icon: const Icon(Icons.navigation_rounded, size: 19),
                                  label: const Text(
                                    'START',
                                    style: TextStyle(
                                      letterSpacing: 0.3,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (!_isSelectingStart)
                            _buildSuggestions(
                              suggestions: _destinationSuggestions,
                              isStart: false,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _onMapViewportChanged(constraints.biggest);

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFDDE5EA),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFBFD0D8)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: InteractiveViewer(
                                    transformationController: _mapTransformationController,
                                    minScale: _minMapScale,
                                    maxScale: _maxMapScale,
                                    constrained: false,
                                    panEnabled: true,
                                    scaleEnabled: true,
                                    onInteractionStart: (_) {
                                      if (_followMeEnabled) {
                                        setState(() {
                                          _followMeEnabled = false;
                                        });
                                      }
                                    },
                                    child: SizedBox(
                                      width: _coordinateMapper.width,
                                      height: _coordinateMapper.height,
                                      child: Builder(
                                        builder: (context) {
                                          if (!_hasLoggedMapRenderSize) {
                                            _hasLoggedMapRenderSize = true;
                                            debugPrint(
                                              'Image render size: ${_coordinateMapper.width}x${_coordinateMapper.height}',
                                            );
                                          }
                                          return Stack(
                                            children: [
                                              Image.asset(
                                                'assets/maps/campus_map.png',
                                                width: _coordinateMapper.width,
                                                height: _coordinateMapper.height,
                                                fit: BoxFit.fill,
                                              ),
                                              IgnorePointer(
                                                child: SizedBox(
                                                  width: _coordinateMapper.width,
                                                  height: _coordinateMapper.height,
                                                  child: CustomPaint(
                                                    painter: RouteOverlayPainter(
                                                      routePixels: _routePixels,
                                                      startPixel: startPixel,
                                                      destinationPixel: destinationPixel,
                                                      currentPixel: _currentLocationPixel,
                                                      headingDegrees: _currentHeadingDegrees,
                                                      sourceWidth: _coordinateMapper.width,
                                                      sourceHeight: _coordinateMapper.height,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 12,
                                  left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.92),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFD6E0E6)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _followMeEnabled
                                              ? Icons.my_location_rounded
                                              : Icons.pan_tool_alt_rounded,
                                          size: 15,
                                          color: _followMeEnabled
                                              ? _primaryTealDark
                                              : const Color(0xFF5F6D77),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _followMeEnabled ? 'Follow enabled' : 'Manual explore',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF22313A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Column(
                          children: [
                            _buildMapControlButton(
                              tooltip: 'Zoom in',
                              icon: Icons.add,
                              onPressed: () => _zoomMap(zoomIn: true),
                            ),
                            const SizedBox(height: 8),
                            _buildMapControlButton(
                              tooltip: 'Zoom out',
                              icon: Icons.remove,
                              onPressed: () => _zoomMap(zoomIn: false),
                            ),
                            const SizedBox(height: 8),
                            _buildMapControlButton(
                              tooltip: _followMeEnabled ? 'Disable follow' : 'Enable follow',
                              icon: _followMeEnabled
                                  ? Icons.my_location_rounded
                                  : Icons.location_searching_rounded,
                              iconColor: _followMeEnabled
                                  ? _primaryTeal
                                  : const Color(0xFF4D5A64),
                              onPressed: () {
                                setState(() {
                                  _followMeEnabled = !_followMeEnabled;
                                });
                                if (_followMeEnabled && _currentLocationPixel != null) {
                                  _centerOnPixel(_currentLocationPixel!);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (_routeInstructions.isNotEmpty &&
              _nextInstructionIndex >= 0 &&
              _nextInstructionIndex < _routeInstructions.length)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFFE5F6FF), Color(0xFFF5FAFF)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC5E4FF)),
              ),
              child: Row(
                children: [
                  Icon(
                    _routeInstructions[_nextInstructionIndex].icon,
                    color: const Color(0xFF1A73E8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _routeInstructions[_nextInstructionIndex].text,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _distanceToNextMeters == null
                              ? 'Updating distance...'
                              : 'In ${_formatDistance(_distanceToNextMeters!)}',
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        if (_distanceToDestinationMeters != null)
                          Text(
                            'Remaining ${_formatDistance(_distanceToDestinationMeters!)}',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_routeInstructions.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              color: const Color(0xFFF5F9FB),
              child: SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final item = _routeInstructions[index];
                    final isActive = index == _nextInstructionIndex;
                    return Container(
                      width: 190,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFFE7F4FF) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFF79B9EE)
                              : const Color(0xFFE0E8EE),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x10000000),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(item.icon, color: _primaryTeal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isActive ? const Color(0xFF0E5A9C) : null,
                                  ),
                                ),
                                if (item.distanceText.isNotEmpty)
                                  Text(
                                    item.distanceText,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemCount: _routeInstructions.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RouteOverlayPainter extends CustomPainter {
  const RouteOverlayPainter({
    required this.routePixels,
    required this.startPixel,
    required this.destinationPixel,
    required this.currentPixel,
    required this.headingDegrees,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final List<Offset> routePixels;
  final Offset? startPixel;
  final Offset? destinationPixel;
  final Offset? currentPixel;
  final double? headingDegrees;
  final double sourceWidth;
  final double sourceHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (routePixels.length < 2) {
      return;
    }

    final scaleX = size.width / sourceWidth;
    final scaleY = size.height / sourceHeight;
    final path = Path()..moveTo(routePixels.first.dx * scaleX, routePixels.first.dy * scaleY);

    for (final point in routePixels.skip(1)) {
      path.lineTo(point.dx * scaleX, point.dy * scaleY);
    }

    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);

    _drawMarker(
      canvas,
      point: startPixel,
      scaleX: scaleX,
      scaleY: scaleY,
      fillColor: const Color(0xFF34A853),
      radius: 9,
    );
    _drawMarker(
      canvas,
      point: destinationPixel,
      scaleX: scaleX,
      scaleY: scaleY,
      fillColor: const Color(0xFFEA4335),
      radius: 9,
    );
    _drawMarker(
      canvas,
      point: currentPixel,
      scaleX: scaleX,
      scaleY: scaleY,
      fillColor: const Color(0xFF4285F4),
      radius: 7,
      drawHalo: true,
      headingDegrees: headingDegrees,
    );
  }

  void _drawMarker(
    Canvas canvas, {
    required Offset? point,
    required double scaleX,
    required double scaleY,
    required Color fillColor,
    required double radius,
    bool drawHalo = false,
    double? headingDegrees,
  }) {
    if (point == null) {
      return;
    }

    final center = Offset(point.dx * scaleX, point.dy * scaleY);
    if (drawHalo) {
      final halo = Paint()
        ..color = fillColor.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius * 2.4, halo);
    }

    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius, stroke);

    if (headingDegrees != null) {
      final headingRad = headingDegrees * (math.pi / 180.0);
      final tip = Offset(
        center.dx + math.sin(headingRad) * (radius * 2.8),
        center.dy - math.cos(headingRad) * (radius * 2.8),
      );
      final left = Offset(
        center.dx + math.sin(headingRad + 2.45) * (radius * 1.2),
        center.dy - math.cos(headingRad + 2.45) * (radius * 1.2),
      );
      final right = Offset(
        center.dx + math.sin(headingRad - 2.45) * (radius * 1.2),
        center.dy - math.cos(headingRad - 2.45) * (radius * 1.2),
      );
      final arrow = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      final arrowPaint = Paint()
        ..color = const Color(0xFF1A73E8)
        ..style = PaintingStyle.fill;
      canvas.drawPath(arrow, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant RouteOverlayPainter oldDelegate) {
    return oldDelegate.routePixels != routePixels ||
        oldDelegate.startPixel != startPixel ||
        oldDelegate.destinationPixel != destinationPixel ||
        oldDelegate.currentPixel != currentPixel ||
        oldDelegate.headingDegrees != headingDegrees;
  }
}

class _RouteInstruction {
  const _RouteInstruction({
    required this.icon,
    required this.text,
    required this.distanceText,
  });

  final IconData icon;
  final String text;
  final String distanceText;
}

class _InstructionBuildResult {
  const _InstructionBuildResult({
    required this.instructions,
    required this.turnPoints,
  });

  final List<_RouteInstruction> instructions;
  final List<_TurnPoint> turnPoints;
}

class _TurnPoint {
  const _TurnPoint({
    required this.instructionIndex,
    required this.pathNodeIndex,
  });

  final int instructionIndex;
  final int pathNodeIndex;
}

class _TurnDescriptor {
  const _TurnDescriptor(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.hint,
    required this.icon,
    required this.controller,
    required this.onTap,
    required this.onChanged,
  });

  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onTap: onTap,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF7D8A95),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF1A7C88)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDCE4EA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFF1DA0AA),
            width: 1.4,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDCE4EA)),
        ),
      ),
    );
  }
}
