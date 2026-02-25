import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import 'eula_consent_screen.dart';
import 'main_tabs_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _authService = AuthService();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  void _register() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final success = await _authService.registerUser(username, password);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      if (success) {
        // После успешной регистрации получаем данные пользователя
        final userData = await StorageService.getUserData();
        if (userData != null && mounted) {
          final userId = userData['id']!;
          final userIdentifier = userData['email'] ?? userData['username'] ?? '';
          final displayName = userData['displayName']?.toString();
          final isSuperuser = userData['isSuperuser'] == 'true';
          final eulaAccepted = await StorageService.getEulaAccepted(userId);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => eulaAccepted
                  ? MainTabsScreen(
                      userId: userId,
                      userEmail: userIdentifier,
                      displayName: displayName,
                      isSuperuser: isSuperuser,
                    )
                  : EulaConsentScreen(
                      userId: userId,
                      userEmail: userIdentifier,
                      displayName: displayName,
                      isSuperuser: isSuperuser,
                    ),
            ),
          );
        } else if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
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
          gradient: const LinearGradient(
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
                            Icons.person_add_rounded,
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
                          'Создать аккаунт',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurfaceDark,
                            letterSpacing: 0.5,
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
                          'Зарегистрируйтесь для начала общения',
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
                  
                  // Форма регистрации с анимацией
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
                                style: const TextStyle(fontSize: 16, color: AppColors.onSurfaceDark),
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
                                  helperText: 'Минимум 4 символа',
                                  helperStyle: TextStyle(
                                    color: AppColors.onSurfaceVariantDark.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                  filled: true,
                                  fillColor: AppColors.primary.withValues(alpha: 0.08),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: AppColors.borderDark),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: AppColors.borderDark),
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
                                style: const TextStyle(fontSize: 16, color: AppColors.onSurfaceDark),
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
                                    borderSide: const BorderSide(color: AppColors.borderDark),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: AppColors.borderDark),
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
                                          style: const TextStyle(
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
                                          onPressed: _register,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text(
                                            'Зарегистрироваться',
                                            style: TextStyle(
                                              color: AppColors.onSurfaceDark,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
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
                    ),
                  const SizedBox(height: 32),
                  // Кнопка входа
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
                        Navigator.pushReplacement(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) =>
                                const LoginScreen(),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Уже есть аккаунт? ',
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
                              'Войти',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
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
