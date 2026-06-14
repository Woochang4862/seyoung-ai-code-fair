import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const SleeplessApp());
}

class SleeplessApp extends StatelessWidget {
  const SleeplessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sleepless',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
