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

  void _register() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    final error = await _authService.registerUser(email, password);

    setState(() {
      _isLoading = false;
      if (error == null) {
        _successMessage = 'Регистрация прошла успешно! Теперь можно войти.';
      } else {
        _errorMessage = error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Регистрация')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _emailController, decoration: InputDecoration(labelText: 'Email')),
            TextField(controller: _passwordController, decoration: InputDecoration(labelText: 'Пароль'), obscureText: true),
            SizedBox(height: 16),
            if (_errorMessage != null) Text(_errorMessage!, style: TextStyle(color: Colors.red)),
            if (_successMessage != null) Text(_successMessage!, style: TextStyle(color: Colors.green)),
            if (_isLoading) CircularProgressIndicator(),
            if (!_isLoading)
              ElevatedButton(onPressed: _register, child: Text('Зарегистрироваться')),
          ],
        ),
      ),
    );
  }
}
