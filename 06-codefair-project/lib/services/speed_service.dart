// GPS 속도 모니터 (experimental-feature)
// ─────────────────────────────────────────────────────────
// 버스가 "멈춰 있을 때"는 졸음 감지 경고를 울리지 않기 위해
// 현재 이동 속도를 GPS로 읽어오는 서비스.
//
// [왜 필요한가]
//   정류장에 정차하거나 신호 대기 중일 때는 기사가 잠깐 눈을 감거나
//   고개를 숙여도 위험하지 않다. 그런데 졸음 알고리즘은 이것을
//   '졸음'으로 오판해 경고음을 울릴 수 있다.
//   → GPS 속도가 거의 0이면(정지) 감지를 잠시 멈춘다.
//
// [동작]
//   - start()  : 위치 권한 확인 후 위치 스트림 구독 시작
//   - speedKmh : 가장 최근 속도(km/h)
//   - isMoving : 속도가 stationarySpeedKmh 이상이면 true(움직임)
//   - onUpdate : 속도가 갱신될 때마다 호출되는 콜백(UI 갱신용)
//   - stop()   : 스트림 해제

import 'dart:async';
import 'package:geolocator/geolocator.dart';

class SpeedService {
  // 이 속도(km/h) 미만이면 '정지'로 본다. 설정 화면에서 바꿀 수 있다.
  double stationarySpeedKmh;

  // 속도가 갱신될 때마다 알려주는 콜백 (화면에서 setState 용)
  final void Function()? onUpdate;

  SpeedService({this.stationarySpeedKmh = 5.0, this.onUpdate});

  StreamSubscription<Position>? _sub;

  // ── 외부에서 읽는 상태 ────────────────────────────────────────
  double speedKmh = 0.0;      // 가장 최근 속도(km/h)
  bool available = false;     // GPS 사용 가능(권한 OK·신호 수신) 여부
  String status = 'GPS 준비 중...';

  // 속도가 '정지 기준'보다 빠르면 움직이는 중.
  // GPS 를 못 쓰면(available=false) 안전하게 '움직임'으로 본다.
  //   → GPS 고장 때문에 졸음 감지가 통째로 꺼지면 더 위험하므로,
  //     불확실하면 감지는 켜 두는 쪽(움직임)으로 판단한다.
  bool get isMoving => !available || speedKmh >= stationarySpeedKmh;

  // ── 시작 ──────────────────────────────────────────────────────
  Future<void> start() async {
    // 1) 위치 서비스(기기 GPS) 켜져 있는지 확인
    if (!await Geolocator.isLocationServiceEnabled()) {
      status = '위치 서비스가 꺼져 있습니다';
      available = false;
      onUpdate?.call();
      return;
    }

    // 2) 위치 권한 확인·요청
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      status = '위치 권한이 필요합니다';
      available = false;
      onUpdate?.call();
      return;
    }

    // 3) 위치 스트림 구독 — 속도(m/s)를 km/h 로 바꿔 저장
    available = true;
    status = 'GPS 작동 중';
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // 멈춰 있어도 속도 갱신을 받기 위해 0
      ),
    ).listen((pos) {
      // position.speed 는 m/s. 음수(미측정)면 0 으로 처리.
      final mps = pos.speed.isNaN || pos.speed < 0 ? 0.0 : pos.speed;
      speedKmh = mps * 3.6;
      onUpdate?.call();
    }, onError: (_) {
      available = false;
      status = 'GPS 신호 오류';
      onUpdate?.call();
    });

    onUpdate?.call();
  }

  // ── 정지 ──────────────────────────────────────────────────────
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
