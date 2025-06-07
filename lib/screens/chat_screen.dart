import 'package:flutter/material.dart';

class ChatScreen extends StatelessWidget {
  final String email;

  ChatScreen({required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Чат'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () {
              // Возврат на экран входа
              Navigator.pushReplacementNamed(context, '/');
            },
          )
        ],
      ),
      body: Center(
        child: Text('Добро пожаловать, $email!'),
      ),
    );
  }
}
