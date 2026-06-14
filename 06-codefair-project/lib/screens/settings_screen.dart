import 'dart:async';

import 'package:flutter/material.dart';
import '../services/speed_service.dart';
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

  // GPS 동작 확인용 라이브 속도 측정기 (GPS 토글이 켜져 있을 때만 동작)
  SpeedService? _speedTest;
  // '마지막 갱신 N초 전'을 1초마다 다시 그리기 위한 타이머.
  // (새 GPS 신호가 안 와도 경과 시간은 계속 올라가야 하므로 별도 타이머 필요)
  Timer? _ticker;

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
      _stationarySpeed = sp.clamp(3.0, 20.0); // 슬라이더 범위 밖 저장값 보호
      _loading = false;
    });
    // GPS 기능이 켜져 있으면 라이브 속도 측정을 바로 시작
    if (_gpsGating) _startSpeedTest();
  }

  // 라이브 속도 측정 시작 — 화면에 현재 속도를 실시간으로 보여줘서
  // GPS 가 잘 동작하는지(권한·신호·속도) 바로 확인할 수 있다.
  Future<void> _startSpeedTest() async {
    if (_speedTest != null) return;
    final svc = SpeedService(
      stationarySpeedKmh: _stationarySpeed,
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
    _speedTest = svc;
    // 1초마다 화면을 다시 그려 '마지막 갱신 N초 전'을 갱신한다.
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    await svc.start();
  }

  Future<void> _stopSpeedTest() async {
    await _speedTest?.stop();
    _speedTest = null;
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _speedTest?.stop();
    _ticker?.cancel();
    super.dispose();
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
              // 토글에 맞춰 라이브 속도 측정 시작/정지
              if (v) {
                await _startSpeedTest();
              } else {
                await _stopSpeedTest();
              }
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
              min: 3, // 2km/h 미만은 떨림으로 0 처리되므로 3부터 의미 있음
              max: 20,
              divisions: 17,
              label: '${_stationarySpeed.toStringAsFixed(0)} km/h',
              onChanged: (v) => setState(() => _stationarySpeed = v),
              onChangeEnd: (v) {
                Storage.saveStationarySpeed(v);
                // 라이브 측정기의 정지 기준도 같이 갱신 → 아래 판정에 즉시 반영
                _speedTest?.stationarySpeedKmh = v;
              },
            ),
            // ── GPS 동작 확인용 라이브 속도 표시 ─────────────────
            _buildSpeedTestPanel(),
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
            title: Text('Sleepless'),
            subtitle: Text('버전 1.0.0 · 한국코드페어 출품작'),
          ),
        ],
      ),
    );
  }

  // GPS 동작 확인용 라이브 속도 패널.
  //   - 권한/신호 상태와 현재 속도(km/h)를 실시간으로 보여준다.
  //   - 지금 기준으로 '정지/주행' 어느 쪽으로 판정되는지도 표시.
  //   → 폰을 들고 걷거나 차로 움직이면 속도가 올라가는지 바로 확인 가능.
  Widget _buildSpeedTestPanel() {
    final svc = _speedTest;

    final bool hasFix = svc != null && svc.available; // GPS 값이 있는지
    final double target = hasFix ? svc.speedKmh : 0.0; // 애니메이션 목표 속도

    late final Color color;
    late final IconData icon;
    late final String sub;

    if (!hasFix) {
      color = Colors.grey;
      icon = Icons.gps_off;
      sub = svc?.status ?? 'GPS 준비 중...';
    } else if (svc.isMoving) {
      color = Colors.blue;
      icon = Icons.directions_bus;
      sub = '주행 중으로 판정 → 졸음 감지 ON';
    } else {
      color = Colors.orange;
      icon = Icons.pause_circle_filled;
      sub = '정지로 판정 → 감지 일시정지';
    }

    // '마지막 갱신: N초 전' — 지금 값이 살아있는지(신호가 계속 오는지) 확인용.
    // 야외에서 GPS 가 정상이면 보통 1~2초마다 갱신된다. 실내·약한 신호에선
    // 몇 초씩 띄엄띄엄 올 수 있어, 10초 넘게 안 와야 '끊김'으로 본다.
    String? freshness;
    Color freshColor = Colors.grey;
    if (svc != null && svc.available) {
      final last = svc.lastUpdate;
      if (last == null) {
        freshness = '아직 위치 신호 없음...';
        freshColor = Colors.orange;
      } else {
        final sec = DateTime.now().difference(last).inSeconds;
        if (sec <= 2) {
          freshness = '마지막 갱신: 방금 전';
          freshColor = Colors.green;
        } else if (sec <= 10) {
          freshness = '마지막 갱신: $sec초 전';
          freshColor = Colors.grey;
        } else {
          freshness = '마지막 갱신: $sec초 전 (신호 끊김?)';
          freshColor = Colors.orange;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '현재 속도 (실시간)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 2),
                  // GPS 는 1초에 한 번 값을 주는데, 숫자가 툭 점프하면 버벅여 보인다.
                  // 새 값으로 0.7초에 걸쳐 부드럽게 미끄러지도록 애니메이션.
                  hasFix
                      ? TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: target),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOut,
                          builder: (_, value, _) => Text(
                            '${value.toStringAsFixed(1)} km/h',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        )
                      : Text(
                          '— km/h',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  if (freshness != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.sync, size: 13, color: freshColor),
                        const SizedBox(width: 4),
                        Text(
                          freshness,
                          style: TextStyle(fontSize: 12, color: freshColor),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
