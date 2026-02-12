import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  @override
  _ForgotPasswordScreenState createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _authService = AuthService();
  final _usernameController = TextEditingController();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _errorMessage;
  bool _isLoading = false;
  String? _resetToken;

  void _requestCode() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => _errorMessage = 'Введите логин');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _resetToken = null;
    });

    try {
      final result = await _authService.requestPasswordReset(username);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _resetToken = result['resetToken'] as String?;
        if (_resetToken != null) {
          _tokenController.text = _resetToken!;
        } else {
          _errorMessage = 'Проверьте правильность логина и попробуйте снова';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _resetPassword() async {
    final token = _tokenController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (token.isEmpty) {
      setState(() => _errorMessage = 'Введите код сброса');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Пароль должен быть не менее 6 символов');
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = 'Пароли не совпадают');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.resetPassword(token, password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Пароль изменён. Войдите с новым паролем.')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
              Color(0xFFf093fb),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_reset, size: 64, color: Colors.white),
                  SizedBox(height: 24),
                  Text(
                    'Сброс пароля',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Введите логин и получите код',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  SizedBox(height: 32),
                  Card(
                    elevation: 12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _usernameController,
                            decoration: InputDecoration(
                              labelText: 'Логин',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            enabled: !_isLoading,
                          ),
                          SizedBox(height: 16),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _requestCode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFF667eea),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading && _resetToken == null
                                  ? SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text('Получить код'),
                            ),
                          ),
                          if (_resetToken != null) ...[
                            SizedBox(height: 24),
                            Text(
                              'Код сброса (действует 15 минут):',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 8),
                            GestureDetector(
                              onLongPress: () {
                                Clipboard.setData(
                                    ClipboardData(text: _resetToken ?? ''));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Код скопирован')),
                                );
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SelectableText(
                                  _resetToken!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 20),
                            TextField(
                              controller: _tokenController,
                              decoration: InputDecoration(
                                labelText: 'Код сброса',
                                hintText: 'Вставьте или введите код',
                                prefixIcon: Icon(Icons.password),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              obscureText: false,
                              enabled: !_isLoading,
                            ),
                            SizedBox(height: 16),
                            TextField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Новый пароль',
                                prefixIcon: Icon(Icons.lock_outline),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              obscureText: true,
                              enabled: !_isLoading,
                            ),
                            SizedBox(height: 16),
                            TextField(
                              controller: _confirmController,
                              decoration: InputDecoration(
                                labelText: 'Повторите пароль',
                                prefixIcon: Icon(Icons.lock_outline),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              obscureText: true,
                              enabled: !_isLoading,
                            ),
                            SizedBox(height: 20),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _resetPassword,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading && _resetToken != null
                                    ? SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text('Сбросить пароль'),
                              ),
                            ),
                          ],
                          if (_errorMessage != null) ...[
                            SizedBox(height: 16),
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline, color: Colors.red),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(color: Colors.red.shade800),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Вернуться ко входу',
                      style: TextStyle(color: Colors.white),
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
