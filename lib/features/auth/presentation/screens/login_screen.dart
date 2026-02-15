import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mycamp_app/features/auth/data/repositories/hive_auth_repository.dart';
import 'package:mycamp_app/features/home/presentation/screens/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final HiveAuthRepository _authRepository = HiveAuthRepository();

  bool get _isLoginEnabled =>
      _usernameController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    await _authRepository.seedDemoUsersIfEmpty();

    final user = await _authRepository.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (user != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const HomeScreen(),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid username or password'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 DESIGN CONSTANTS (MATCHES REFERENCE IMAGE)
    const cardRadius = 24.0;
    const fieldRadius = 14.0;

    const primaryTeal = Color(0xFF1DA0AA);
    const accentCyan = Color(0xFF39C3CF);

    const textPrimary = Color(0xFF1E1F22);
    const textMuted = Color(0xFF6A7075);
    const footerTeal = Color(0xFF256A6B);

    return Scaffold(
      body: Stack(
        children: [
          // 🔹 Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/auth/login_bg.png',
              fit: BoxFit.cover,
              alignment: const Alignment(0.4, 0.4)
            ),
          ),

          // 🔹 Dark overlay for readability
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.30),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(cardRadius),
                  child: BackdropFilter(
                    filter:
                        ImageFilter.blur(sigmaX: 5,  sigmaY: 5), // ✅ correct blur
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.88,
                      padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.24),
                        borderRadius:
                            BorderRadius.circular(cardRadius),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 24,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 🔹 Logo
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFE9FCFD),
                                    Color(0xFFCDECF0)
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.explore,
                                size: 32,
                                color: primaryTeal,
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // 🔹 App title
                          const Text(
                            'MyCamp',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),

                          const SizedBox(height: 6),

                          const Text(
                            'Campus Navigation',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: textPrimary,
                            ),
                          ),

                          const SizedBox(height: 32),

                          // 🔹 Username field
                          SizedBox(
                            height: 52,
                            child: TextFormField(
                              controller: _usernameController,
                              onChanged: (_) => setState(() {}),
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(
                                fontSize: 16,
                                color: textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Username',
                                hintStyle: const TextStyle(
                                  color: textMuted,
                                  fontSize: 16,
                                ),
                                prefixIcon:
                                    const Icon(Icons.person_outline),
                                prefixIconColor: primaryTeal,
                                filled: true,
                                fillColor:
                                    Colors.white.withValues(alpha: 0.65),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(fieldRadius),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(fieldRadius),
                                  borderSide: const BorderSide(
                                    color: primaryTeal,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // 🔹 Password field
                          SizedBox(
                            height: 52,
                            child: TextFormField(
                              controller: _passwordController,
                              onChanged: (_) => setState(() {}),
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              style: const TextStyle(
                                fontSize: 16,
                                color: textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Password',
                                hintStyle: const TextStyle(
                                  color: textMuted,
                                  fontSize: 16,
                                ),
                                prefixIcon:
                                    const Icon(Icons.lock_outline),
                                prefixIconColor: primaryTeal,
                                filled: true,
                                fillColor:
                                    Colors.white.withValues(alpha: 0.65),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(fieldRadius),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(fieldRadius),
                                  borderSide: const BorderSide(
                                    color: primaryTeal,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 22),

                          // 🔹 Login button
                          SizedBox(
                            height: 48,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [primaryTeal, accentCyan],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x33195457),
                                    blurRadius: 16,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed:
                                    _isLoginEnabled ? _handleLogin : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  disabledBackgroundColor:
                                      Colors.white.withValues(alpha: 0.4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'LOGIN',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // 🔹 Forgot password
                          TextButton(
                            onPressed: () {},
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: footerTeal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
