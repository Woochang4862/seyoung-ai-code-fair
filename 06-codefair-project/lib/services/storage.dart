import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// 졸음 감지 한 건의 기록
class DrowsyEvent {
  final DateTime time;
  final double leftEyeOpen;
  final double rightEyeOpen;

  DrowsyEvent({
    required this.time,
    required this.leftEyeOpen,
    required this.rightEyeOpen,
  });

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'left': leftEyeOpen,
        'right': rightEyeOpen,
      };

  factory DrowsyEvent.fromJson(Map<String, dynamic> json) => DrowsyEvent(
        time: DateTime.parse(json['time'] as String),
        leftEyeOpen: (json['left'] as num).toDouble(),
        rightEyeOpen: (json['right'] as num).toDouble(),
      );
}

// 설정 + 기록을 SharedPreferences로 저장하는 단일 저장소
class Storage {
  static const _kThreshold = 'eye_threshold';
  static const _kSoundOn = 'sound_on';
  static const _kHistory = 'history';

  // ── 설정 ──────────────────────────────────────────────────────
  static Future<double> loadThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kThreshold) ?? 0.25; // 파이썬 EAR_THRESHOLD 와 동일
  }

  static Future<void> saveThreshold(double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kThreshold, v);
  }

  static Future<bool> loadSoundOn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSoundOn) ?? true;
  }

  static Future<void> saveSoundOn(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSoundOn, v);
  }

  // ── 기록 ──────────────────────────────────────────────────────
  static Future<List<DrowsyEvent>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kHistory) ?? [];
    final events = raw
        .map((s) => DrowsyEvent.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    return events.reversed.toList(); // 최신이 위로
  }

  static Future<void> addEvent(DrowsyEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kHistory) ?? [];
    list.add(jsonEncode(event.toJson()));
    if (list.length > 100) list.removeAt(0); // 최근 100건만 유지
    await prefs.setStringList(_kHistory, list);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHistory);
  }
}
