import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  Future<void> _register() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // Простая валидация
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Пожалуйста, заполните все поля';
      });
      return;
    }

    final error = await _authService.registerUser(email, password);

    setState(() {
      _isLoading = false;
      if (error == null) {
        _successMessage = 'Регистрация прошла успешно! Теперь можно войти.';
        _emailController.clear();
        _passwordController.clear();
      } else {
        _errorMessage = error;
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Регистрация')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: 'Пароль'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null) Text(_errorMessage!, style: TextStyle(color: Colors.red)),
            if (_successMessage != null) Text(_successMessage!, style: TextStyle(color: Colors.green)),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            if (!_isLoading)
              ElevatedButton(
                onPressed: _register,
                child: Text('Зарегистрироваться'),
              ),
          ],
        ),
      ),
    );
  }
}
