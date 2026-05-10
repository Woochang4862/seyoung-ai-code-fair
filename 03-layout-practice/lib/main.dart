import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Layout Practice',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('레이아웃 연습'),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
        ),
        body: const LayoutDemo(),
      ),
    );
  }
}

class LayoutDemo extends StatelessWidget {
  const LayoutDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 예제
          const Text('Row (가로 배치)',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: const [
              Icon(Icons.star, color: Colors.amber, size: 40),
              Icon(Icons.star, color: Colors.amber, size: 40),
              Icon(Icons.star, color: Colors.amber, size: 40),
            ],
          ),
          const Divider(height: 32),

          // Column 예제
          const Text('Column (세로 배치)',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Column(
            children: const [
              Text('첫 번째 줄'),
              Text('두 번째 줄'),
              Text('세 번째 줄'),
            ],
          ),
          const Divider(height: 32),

          // Center + Padding 예제
          const Text('Center + Padding',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            color: Colors.orange[100],
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  '여백과 가운데 정렬',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
          const Divider(height: 32),

          // mainAxisAlignment 비교
          const Text('mainAxisAlignment 비교',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildAlignDemo('start', MainAxisAlignment.start),
          _buildAlignDemo('center', MainAxisAlignment.center),
          _buildAlignDemo('end', MainAxisAlignment.end),
          _buildAlignDemo('spaceBetween', MainAxisAlignment.spaceBetween),
          _buildAlignDemo('spaceEvenly', MainAxisAlignment.spaceEvenly),
          _buildAlignDemo('spaceAround', MainAxisAlignment.spaceAround),
        ],
      ),
    );
  }

  Widget _buildAlignDemo(String label, MainAxisAlignment alignment) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Container(
            color: Colors.grey[200],
            child: Row(
              mainAxisAlignment: alignment,
              children: const [
                Icon(Icons.favorite, color: Colors.red),
                Icon(Icons.favorite, color: Colors.red),
                Icon(Icons.favorite, color: Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
