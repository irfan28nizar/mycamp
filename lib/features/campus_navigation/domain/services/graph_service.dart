import 'dart:math' as math;

import 'package:mycamp_app/features/campus_navigation/data/models/edge_model.dart';
import 'package:mycamp_app/features/campus_navigation/data/models/node_model.dart';

class GraphService {
  GraphService(
    List<NodeModel> nodes,
    List<EdgeModel> edges,
  )   : _nodesById = {
          for (final node in nodes) node.id: node,
        },
        _adjacency = _buildAdjacency(edges);

  static const double _earthRadiusMeters = 6371000;

  final Map<int, NodeModel> _nodesById;
  final Map<int, List<_Neighbor>> _adjacency;

  List<int> findShortestPath(int startId, int endId, String mode) {
    final normalizedMode = mode.toLowerCase();
    if (normalizedMode != 'walk' && normalizedMode != 'drive') {
      throw ArgumentError.value(mode, 'mode', 'Mode must be "walk" or "drive".');
    }

    if (!_nodesById.containsKey(startId) || !_nodesById.containsKey(endId)) {
      return <int>[];
    }

    if (startId == endId) {
      return <int>[startId];
    }

    final distances = <int, double>{
      for (final nodeId in _nodesById.keys) nodeId: double.infinity,
    };
    final previous = <int, int>{};
    final queue = _MinHeap();

    distances[startId] = 0;
    queue.push(_QueueNode(nodeId: startId, distance: 0));

    while (!queue.isEmpty) {
      final current = queue.pop();
      if (current == null) {
        break;
      }

      if (current.distance > (distances[current.nodeId] ?? double.infinity)) {
        continue;
      }

      if (current.nodeId == endId) {
        break;
      }

      final neighbors = _adjacency[current.nodeId] ?? const <_Neighbor>[];
      for (final neighbor in neighbors) {
        if (!_isEdgeAllowed(normalizedMode, neighbor.type)) {
          continue;
        }

        final edgeDistance = _haversineDistanceMeters(current.nodeId, neighbor.toNodeId);
        final candidateDistance = current.distance + edgeDistance;

        if (candidateDistance < (distances[neighbor.toNodeId] ?? double.infinity)) {
          distances[neighbor.toNodeId] = candidateDistance;
          previous[neighbor.toNodeId] = current.nodeId;
          queue.push(
            _QueueNode(
              nodeId: neighbor.toNodeId,
              distance: candidateDistance,
            ),
          );
        }
      }
    }

    if ((distances[endId] ?? double.infinity) == double.infinity) {
      return <int>[];
    }

    final path = <int>[];
    var cursor = endId;
    path.add(cursor);

    while (cursor != startId) {
      final parent = previous[cursor];
      if (parent == null) {
        return <int>[];
      }
      cursor = parent;
      path.add(cursor);
    }

    return path.reversed.toList(growable: false);
  }

  static Map<int, List<_Neighbor>> _buildAdjacency(List<EdgeModel> edges) {
    final adjacency = <int, List<_Neighbor>>{};

    for (final edge in edges) {
      adjacency.putIfAbsent(edge.from, () => <_Neighbor>[]).add(
            _Neighbor(toNodeId: edge.to, type: edge.type.toLowerCase()),
          );
      adjacency.putIfAbsent(edge.to, () => <_Neighbor>[]).add(
            _Neighbor(toNodeId: edge.from, type: edge.type.toLowerCase()),
          );
    }

    return adjacency;
  }

  bool _isEdgeAllowed(String mode, String edgeType) {
    if (mode == 'walk') {
      return edgeType == 'walk' || edgeType == 'drive';
    }
    if (mode == 'drive') {
      return edgeType == 'drive';
    }
    return false;
  }

  double _haversineDistanceMeters(int fromNodeId, int toNodeId) {
    final fromNode = _nodesById[fromNodeId];
    final toNode = _nodesById[toNodeId];

    if (fromNode == null || toNode == null) {
      return double.infinity;
    }

    final lat1 = _toRadians(fromNode.lat);
    final lon1 = _toRadians(fromNode.lng);
    final lat2 = _toRadians(toNode.lat);
    final lon2 = _toRadians(toNode.lng);

    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;

    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return _earthRadiusMeters * c;
  }

  double _toRadians(double degrees) => degrees * (math.pi / 180.0);
}

class _Neighbor {
  const _Neighbor({
    required this.toNodeId,
    required this.type,
  });

  final int toNodeId;
  final String type;
}

class _QueueNode {
  const _QueueNode({
    required this.nodeId,
    required this.distance,
  });

  final int nodeId;
  final double distance;
}

class _MinHeap {
  final List<_QueueNode> _heap = <_QueueNode>[];

  bool get isEmpty => _heap.isEmpty;

  void push(_QueueNode value) {
    _heap.add(value);
    _siftUp(_heap.length - 1);
  }

  _QueueNode? pop() {
    if (_heap.isEmpty) {
      return null;
    }

    final first = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      _siftDown(0);
    }
    return first;
  }

  void _siftUp(int index) {
    var child = index;
    while (child > 0) {
      final parent = (child - 1) ~/ 2;
      if (_heap[parent].distance <= _heap[child].distance) {
        break;
      }
      final tmp = _heap[parent];
      _heap[parent] = _heap[child];
      _heap[child] = tmp;
      child = parent;
    }
  }

  void _siftDown(int index) {
    var parent = index;
    while (true) {
      final left = (2 * parent) + 1;
      final right = left + 1;
      var smallest = parent;

      if (left < _heap.length &&
          _heap[left].distance < _heap[smallest].distance) {
        smallest = left;
      }
      if (right < _heap.length &&
          _heap[right].distance < _heap[smallest].distance) {
        smallest = right;
      }
      if (smallest == parent) {
        break;
      }

      final tmp = _heap[parent];
      _heap[parent] = _heap[smallest];
      _heap[smallest] = tmp;
      parent = smallest;
    }
  }
}
