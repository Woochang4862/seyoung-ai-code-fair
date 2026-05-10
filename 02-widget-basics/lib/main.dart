import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Widget Basics',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('기본 위젯 연습'),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: const WidgetGallery(),
      ),
    );
  }
}

class WidgetGallery extends StatelessWidget {
  const WidgetGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Text 위젯
          const Text(
            '1. Text 위젯',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('기본 텍스트입니다.'),
          const Text(
            '스타일 적용된 텍스트',
            style: TextStyle(
              fontSize: 20,
              color: Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),

          // 2. Container 위젯
          const Text(
            '2. Container 위젯',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            width: 200,
            height: 80,
            color: Colors.yellow,
            alignment: Alignment.center,
            child: const Text('노란 박스'),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '둥근 파란 박스',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
          const SizedBox(height: 24),

          // 3. Icon 위젯
          const Text(
            '3. Icon 위젯',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Icon(Icons.home),
              SizedBox(width: 8),
              Icon(Icons.favorite, color: Colors.red),
              SizedBox(width: 8),
              Icon(Icons.star, size: 40, color: Colors.amber),
            ],
          ),
          const SizedBox(height: 24),

          // 4. Image 위젯 (네트워크 이미지)
          const Text(
            '4. Image 위젯',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Image.network(
            'https://picsum.photos/300/150',
            errorBuilder: (context, error, stackTrace) => Container(
              width: 300,
              height: 150,
              color: Colors.grey,
              alignment: Alignment.center,
              child: const Text('이미지 로드 실패'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
