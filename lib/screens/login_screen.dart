import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/storage_service.dart';
import 'eula_consent_screen.dart';
import 'main_tabs_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _LoginScreenState createState() => _LoginScreenState();
}


//
class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  void _login() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final userData = await _authService.loginUser(username, password);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      if (userData != null && userData['token'] != null) {
        final userId = userData['id'].toString();
        final userIdentifier = userData['username'] ?? userData['email'] ?? '';
        final isSuperuser = userData['isSuperuser'] == true;
        final displayName = userData['displayName']?.toString();
        final eulaAccepted = await StorageService.getEulaAccepted(userId);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => eulaAccepted
                  ? MainTabsScreen(
                      userId: userId,
                      userEmail: userIdentifier.toString(),
                      displayName: displayName,
                      isSuperuser: isSuperuser,
                    )
                  : EulaConsentScreen(
                      userId: userId,
                      userEmail: userIdentifier.toString(),
                      displayName: displayName,
                      isSuperuser: isSuperuser,
                    ),
            ),
          ).then((_) => PushNotificationService.sendTokenToBackendIfNeeded());
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Неверный логин или пароль';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.backgroundDark,
              AppColors.surfaceDark,
              AppColors.primaryDeep,
              AppColors.primary,
            ],
            stops: [0.0, 0.35, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Логотип/Иконка с анимацией
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Container(
                          width: 120,
                          height: 120,
                    decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.cardDark,
                                AppColors.surfaceDark,
                              ],
                            ),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primaryGlow.withValues(alpha: 0.5), width: 2),
                      boxShadow: [
                        ...AppColors.neonGlow,
                        BoxShadow(
                          color: AppColors.primaryGlow.withValues(alpha: 0.3),
                          blurRadius: 32,
                          spreadRadius: -4,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                            Icons.chat_bubble_rounded,
                            size: 60,
                            color: AppColors.primaryGlow,
                          ),
                    ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  
                  // Заголовок с анимацией
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      children: [
                  Text(
                    'Reol',
                    style: TextStyle(
                            fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurfaceDark,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(
                                color: AppColors.primaryGlow.withValues(alpha: 0.8),
                                blurRadius: 24,
                                offset: const Offset(0, 0),
                              ),
                              Shadow(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                blurRadius: 12,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                  ),
                        const SizedBox(height: 12),
                  Text(
                    'Войдите в свой аккаунт',
                    style: TextStyle(
                            fontSize: 18,
                            color: AppColors.onSurfaceVariantDark,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 50),
                  
                  // Форма входа с анимацией
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 30 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: AppColors.cardDark,
                        border: Border.all(color: AppColors.primaryGlow.withValues(alpha: 0.35)),
                        boxShadow: AppColors.neonGlowSoft,
                      ),
                      child: Padding(
                          padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                              // Поле логина
                              TextField(
                                  controller: _usernameController,
                                  keyboardType: TextInputType.text,
                                  style: TextStyle(fontSize: 16, color: AppColors.onSurfaceDark),
                            decoration: InputDecoration(
                                    labelText: 'Логин',
                                    prefixIcon: const Icon(
                                      Icons.person_outlined,
                                      color: AppColors.primaryGlow,
                                    ),
                                    labelStyle: TextStyle(
                                      color: AppColors.onSurfaceVariantDark,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    filled: true,
                                    fillColor: AppColors.primary.withValues(alpha: 0.08),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.borderDark),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.borderDark),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.primaryGlow, width: 2),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 20),
                              // Поле пароля
                              TextField(
                            controller: _passwordController,
                                  style: TextStyle(fontSize: 16, color: AppColors.onSurfaceDark),
                            decoration: InputDecoration(
                              labelText: 'Пароль',
                                    prefixIcon: const Icon(
                                      Icons.lock_outlined,
                                      color: AppColors.primaryGlow,
                                    ),
                                    labelStyle: TextStyle(
                                      color: AppColors.onSurfaceVariantDark,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    filled: true,
                                    fillColor: AppColors.primary.withValues(alpha: 0.08),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.borderDark),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.borderDark),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.primaryGlow, width: 2),
                                    ),
                            ),
                            obscureText: true,
                          ),
                              const SizedBox(height: 28),
                          if (_errorMessage != null)
                            Container(
                                  padding: const EdgeInsets.all(14),
                                  margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.red.withValues(alpha: 0.5),
                                    ),
                              ),
                              child: Row(
                                children: [
                                      Icon(
                                        Icons.error_outline_rounded,
                                        color: Colors.red.shade300,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                          style: TextStyle(
                                            color: AppColors.onSurfaceDark,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          SizedBox(
                                height: 56,
                            child: _isLoading
                                    ? const Center(
                                        child: CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            AppColors.primaryGlow,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          gradient: const LinearGradient(
                                            colors: [
                                              AppColors.primary,
                                              AppColors.primaryDeep,
                                            ],
                                          ),
                                          boxShadow: AppColors.neonGlow,
                                        ),
                                        child: ElevatedButton(
                                    onPressed: _login,
                                    style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                    ),
                                          child: const Text(
                                            'Войти',
                                            style: TextStyle(
                                              color: AppColors.onSurfaceDark,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                  ),
                            ),
                        ],
                          ),
                        ),
                        ),
                  ), // TweenAnimationBuilder
                  const SizedBox(height: 32),
                  
                  // Кнопка регистрации
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: child,
                      );
                    },
                    child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) =>
                                const RegisterScreen(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                          ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onSurfaceVariantDark,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Нет аккаунта?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: AppColors.onSurfaceVariantDark,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.primaryGlow.withValues(alpha: 0.7),
                              width: 1.5,
                            ),
                          ),
                          child: const Text(
                            'Зарегистрироваться',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
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
      ),
    );
  }
}
