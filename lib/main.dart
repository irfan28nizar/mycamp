import 'package:flutter/material.dart';
import 'package:mycamp_app/core/storage/hive_initializer.dart';
import 'package:mycamp_app/features/auth/presentation/screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveInitializer.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyCamp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1DA0AA)),
        scaffoldBackgroundColor: const Color(0xFFF6F2FA),
      ),
      home: const LoginScreen(),
    );
  }
}
