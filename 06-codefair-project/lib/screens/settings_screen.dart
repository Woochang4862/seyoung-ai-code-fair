import 'package:flutter/material.dart';
import '../services/storage.dart';
import 'calibration_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _threshold = 0.3;
  bool _soundOn = true;
  bool _loading = true;

  // 실험 기능(experimental-feature) 설정값
  bool _gpsGating = false;
  double _stationarySpeed = 5.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await Storage.loadThreshold();
    final s = await Storage.loadSoundOn();
    final g = await Storage.loadGpsGating();
    final sp = await Storage.loadStationarySpeed();
    if (!mounted) return;
    setState(() {
      _threshold = t;
      _soundOn = s;
      _gpsGating = g;
      _stationarySpeed = sp;
      _loading = false;
    });
  }

  // 자동 보정 화면을 열고, 돌아오면 새 임계값을 다시 읽어 슬라이더에 반영
  Future<void> _openCalibration() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CalibrationScreen()),
    );
    final t = await Storage.loadThreshold();
    if (!mounted) return;
    setState(() => _threshold = t);
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
          // 실험 기능: 카메라로 직접 측정해 내 눈에 맞는 민감도 찾기
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openCalibration,
                icon: const Icon(Icons.face_retouching_natural),
                label: const Text('민감도 자동 보정 (실험)'),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '카메라로 내 눈을 측정해 가장 알맞은 민감도를 자동으로 찾아줍니다.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
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
          // ── 실험 기능: GPS 정지 게이팅 ─────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '실험 기능',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          SwitchListTile(
            title: const Text('정지 시 감지 끄기 (GPS)'),
            subtitle: const Text(
              '버스가 멈춰 있을 때(정류장·신호 대기)는\n경고를 울리지 않습니다',
            ),
            value: _gpsGating,
            onChanged: (v) async {
              setState(() => _gpsGating = v);
              await Storage.saveGpsGating(v);
            },
          ),
          if (_gpsGating) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '정지 판단 속도: ${_stationarySpeed.toStringAsFixed(0)} km/h 미만이면 정지로 봅니다.',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ),
            Slider(
              value: _stationarySpeed,
              min: 1,
              max: 20,
              divisions: 19,
              label: '${_stationarySpeed.toStringAsFixed(0)} km/h',
              onChanged: (v) => setState(() => _stationarySpeed = v),
              onChangeEnd: (v) => Storage.saveStationarySpeed(v),
            ),
          ],
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
