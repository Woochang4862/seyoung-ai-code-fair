import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════
//  📝 도전 과제 (완성한 정답이 궁금하면: git checkout solution)
//  1) 프로필 아이콘을 실제 이미지(Image.network)로 바꾸기
//     힌트: https://picsum.photos/120
//  2) 배경색/폰트/아이콘 3군데 이상 자기 스타일로 바꾸기
//  3) 새로운 위젯 1개 추가 (공식 문서에서 찾아보기)
//     후보: Chip, Wrap, LinearProgressIndicator, Divider, etc.
// ═══════════════════════════════════════════════════════════

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Profile Card',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('프로필 카드'),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
        ),
        backgroundColor: Colors.blue[50],
        body: const Center(
          child: ProfileCard(),
        ),
      ),
    );
  }
}

class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // TODO 도전 1: 아래 Icon을 Image.network로 바꿔보세요
          const Icon(
            Icons.account_circle,
            size: 100,
            color: Colors.indigo,
          ),
          const SizedBox(height: 16),

          // 이름
          const Text(
            '김민성',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),

          // 학교
          Text(
            '길음중학교 3학년',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),

          // 꿈
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.star, color: Colors.amber),
              SizedBox(width: 8),
              Text(
                '꿈: 개발자',
                style: TextStyle(fontSize: 18),
              ),
              SizedBox(width: 8),
              Icon(Icons.star, color: Colors.amber),
            ],
          ),
          const SizedBox(height: 24),

          // TODO 도전 3: 여기에 새로운 위젯을 추가해보세요
          // 예: 관심분야 Chip, 진행률 바, 구분선, 등등

          // 버튼 영역
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.favorite),
                label: const Text('좋아요'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink[100],
                  foregroundColor: Colors.pink[900],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.message),
                label: const Text('메시지'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo[100],
                  foregroundColor: Colors.indigo[900],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
