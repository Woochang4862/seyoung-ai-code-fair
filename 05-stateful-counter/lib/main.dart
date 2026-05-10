import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stateful Counter',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('좋아요 카운터'),
          backgroundColor: Colors.pink,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: LikeCounter(),
        ),
      ),
    );
  }
}

// StatefulWidget: 화면이 바뀌는 위젯
class LikeCounter extends StatefulWidget {
  const LikeCounter({super.key});

  @override
  State<LikeCounter> createState() => _LikeCounterState();
}

class _LikeCounterState extends State<LikeCounter> {
  int _likes = 0; // 현재 좋아요 수 (상태)

  void _addLike() {
    // setState를 호출해야 화면이 업데이트됨!
    setState(() {
      _likes++;
    });
  }

  void _resetLikes() {
    setState(() {
      _likes = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.favorite, size: 80, color: Colors.pink),
        const SizedBox(height: 16),
        Text(
          '$_likes',
          style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold),
        ),
        const Text('좋아요', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _addLike,
              icon: const Icon(Icons.add),
              label: const Text('좋아요 +1'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: _resetLikes,
              icon: const Icon(Icons.refresh),
              label: const Text('초기화'),
            ),
          ],
        ),
      ],
    );
  }
}
