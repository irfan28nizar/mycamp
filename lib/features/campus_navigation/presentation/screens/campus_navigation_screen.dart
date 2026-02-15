import 'package:flutter/material.dart';
import 'package:mycamp_app/features/auth/data/repositories/hive_auth_repository.dart';
import 'package:mycamp_app/features/auth/presentation/screens/login_screen.dart';
import 'package:mycamp_app/features/admin/presentation/screens/admin_screen.dart';

class CampusNavigationScreen extends StatefulWidget {
  const CampusNavigationScreen({super.key});

  @override
  State<CampusNavigationScreen> createState() => _CampusNavigationScreenState();
}

class _CampusNavigationScreenState extends State<CampusNavigationScreen> {
  final HiveAuthRepository _authRepository = HiveAuthRepository();
  late final Future<String?> _currentUserRoleFuture;

  @override
  void initState() {
    super.initState();
    _currentUserRoleFuture = _loadCurrentUserRole();
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
                    ),
                    const SizedBox(height: 10),
                    _SearchField(
                      hintText: 'where to...',
                    ),
                    const SizedBox(height: 14),
                    Align(
                      child: SizedBox(
                        height: 36,
                        child: ElevatedButton(
                          onPressed: () {},
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
              child: Container(
                width: double.infinity,
                color: const Color(0xFFE5E5E5),
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/images/campus_map.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hintText});

  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }
}
