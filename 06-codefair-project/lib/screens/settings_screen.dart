import 'package:flutter/material.dart';
import '../services/storage.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _threshold = 0.3;
  bool _soundOn = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await Storage.loadThreshold();
    final s = await Storage.loadSoundOn();
    if (!mounted) return;
    setState(() {
      _threshold = t;
      _soundOn = s;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              '졸음 판정 민감도',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'EAR(눈 종횡비) 값이 ${_threshold.toStringAsFixed(2)} 미만이면 눈을 감은 것으로 봅니다.\n'
              '값이 높을수록 더 쉽게 감았다고 판정합니다.\n'
              '권장값: 0.25 (파이썬 EAR_THRESHOLD 와 동일)',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
          ),
          Slider(
            value: _threshold,
            min: 0.10,
            max: 0.40,
            divisions: 30,
            label: _threshold.toStringAsFixed(2),
            onChanged: (v) => setState(() => _threshold = v),
            onChangeEnd: (v) => Storage.saveThreshold(v),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('경고음'),
            subtitle: const Text('졸음 감지 시 소리로 알립니다'),
            value: _soundOn,
            onChanged: (v) async {
              setState(() => _soundOn = v);
              await Storage.saveSoundOn(v);
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              '앱 정보',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('안전 운전 도우미'),
            subtitle: Text('버전 1.0.0 · 한국코드페어 출품작'),
          ),
        ],
      ),
    );
  }
}
