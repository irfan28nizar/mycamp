import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:mycamp_app/features/auth/domain/models/user.dart';
import 'package:mycamp_app/features/auth/domain/repositories/auth_repository.dart';

class HiveAuthRepository implements AuthRepository {
  HiveAuthRepository({HiveInterface? hive}) : _hive = hive ?? Hive;

  static const String usersBoxName = 'auth_users';
  static const String sessionBoxName = 'auth_session';
  static const String currentUserIdKey = 'current_user_id';

  final HiveInterface _hive;

  @override
  Future<User?> login(String username, String password) async {
    final usersBox = await _openUsersBox();
    final savedUserMap = usersBox.get(_normalizeUsername(username));

    if (savedUserMap == null) {
      return null;
    }

    final storedUser = _StoredUser.fromMap(savedUserMap);
    final incomingPasswordHash = hashPassword(password);

    if (incomingPasswordHash != storedUser.passwordHash) {
      return null;
    }

    final sessionBox = await _openSessionBox();
    await sessionBox.put(currentUserIdKey, storedUser.id);

    return storedUser.toDomainUser();
  }

  @override
  Future<User?> getCurrentUser() async {
    final sessionBox = await _openSessionBox();
    final currentUserId = sessionBox.get(currentUserIdKey) as String?;

    if (currentUserId == null || currentUserId.isEmpty) {
      return null;
    }

    final usersBox = await _openUsersBox();
    for (final userMap in usersBox.values) {
      final storedUser = _StoredUser.fromMap(userMap);
      if (storedUser.id == currentUserId) {
        return storedUser.toDomainUser();
      }
    }

    return null;
  }

  @override
  Future<void> logout() async {
    final sessionBox = await _openSessionBox();
    await sessionBox.delete(currentUserIdKey);
  }

  Future<void> upsertUser(User user, String password) async {
    final usersBox = await _openUsersBox();
    final storedUser = _StoredUser.fromDomainUser(
      user,
      passwordHash: hashPassword(password),
    );
    await usersBox.put(_normalizeUsername(user.username), storedUser.toMap());
  }

  Future<void> seedDemoUsersIfEmpty() async {
    final usersBox = await _openUsersBox();
    if (usersBox.isNotEmpty) {
      return;
    }

    // Seed minimal offline demo accounts for local authentication testing.
    final demoUsers = <_StoredUser>[
      _StoredUser(
        id: '1',
        username: 'admin',
        passwordHash: hashPassword('admin123'),
        role: 'admin',
      ),
      _StoredUser(
        id: '2',
        username: 'student',
        passwordHash: hashPassword('student123'),
        role: 'student',
      ),
    ];

    for (final user in demoUsers) {
      await usersBox.put(_normalizeUsername(user.username), user.toMap());
    }
  }

  static String hashPassword(String value) {
    // Lightweight deterministic hash placeholder for local-only foundation.
    const int fnvOffset = 0x811C9DC5;
    const int fnvPrime = 0x01000193;
    var hash = fnvOffset;

    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }

    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<Box<Map<dynamic, dynamic>>> _openUsersBox() async {
    if (_hive.isBoxOpen(usersBoxName)) {
      return _hive.box<Map<dynamic, dynamic>>(usersBoxName);
    }
    return _hive.openBox<Map<dynamic, dynamic>>(usersBoxName);
  }

  Future<Box<dynamic>> _openSessionBox() async {
    if (_hive.isBoxOpen(sessionBoxName)) {
      return _hive.box(sessionBoxName);
    }
    return _hive.openBox(sessionBoxName);
  }

  String _normalizeUsername(String username) {
    return username.trim().toLowerCase();
  }
}

class _StoredUser {
  const _StoredUser({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.role,
  });

  final String id;
  final String username;
  final String passwordHash;
  final String role;

  User toDomainUser() {
    return User(
      id: id,
      username: username,
      role: role,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'passwordHash': passwordHash,
      'role': role,
    };
  }

  factory _StoredUser.fromMap(Map<dynamic, dynamic> map) {
    return _StoredUser(
      id: (map['id'] ?? '') as String,
      username: (map['username'] ?? '') as String,
      passwordHash: (map['passwordHash'] ?? '') as String,
      role: (map['role'] ?? '') as String,
    );
  }

  factory _StoredUser.fromDomainUser(
    User user, {
    required String passwordHash,
  }) {
    return _StoredUser(
      id: user.id,
      username: user.username,
      passwordHash: passwordHash,
      role: user.role,
    );
  }
}
