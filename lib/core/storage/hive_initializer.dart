import 'package:hive_flutter/hive_flutter.dart';

class HiveInitializer {
  HiveInitializer._();

  static const String usersBoxName = 'auth_users';
  static const String sessionBoxName = 'auth_session';
  static const String navigationBoxName = 'campus_navigation';

  static Future<void> init() async {
    // Initializes Hive with a Flutter-compatible storage path.
    await Hive.initFlutter();

    // Pre-opens auth boxes for offline local authentication reads/writes.
    await Hive.openBox<Map<dynamic, dynamic>>(usersBoxName);
    await Hive.openBox<dynamic>(sessionBoxName);
    await Hive.openBox<dynamic>(navigationBoxName);
  }
}
