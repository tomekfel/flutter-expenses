import 'package:flutter/material.dart';
import 'package:notes_app/pages/VoiceExpensePage.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const VoiceExpensePage(),
    );
  }
}