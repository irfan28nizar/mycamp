class User {
  const User({
    required this.id,
    required this.username,
    required this.role,
  });

  final String id;
  final String username;
  final String role;

  User copyWith({
    String? id,
    String? username,
    String? role,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      role: role ?? this.role,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'role': role,
    };
  }

  factory User.fromMap(Map<dynamic, dynamic> map) {
    return User(
      id: (map['id'] ?? '') as String,
      username: (map['username'] ?? '') as String,
      role: (map['role'] ?? '') as String,
    );
  }
}
