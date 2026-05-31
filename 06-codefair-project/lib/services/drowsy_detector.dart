// 운전자 상태 감지 알고리즘
// ─────────────────────────────────────────────────────────
// 파이썬 07-ai-python/18_state_machine.py 의 Flutter 포팅 버전.
//
// [차이점]
//   파이썬: MediaPipe FaceLandmarker 의 478개 랜드마크 사용
//   Flutter: ML Kit FaceDetection 의 FaceContour(눈 윤곽 16점) 사용
//   → 랜드마크 형태는 다르지만 EAR 계산식과 상태 머신 로직은 동일.
//
// [상태 정의]
//   NORMAL     이상 없음
//   DROWSY     눈이 일정 시간 이상 감겨 있음
//   COLLAPSED  쓰러지거나 얼굴이 오래 사라짐

import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum DriverState { normal, drowsy, collapsed }

extension DriverStateLabel on DriverState {
  String get label {
    switch (this) {
      case DriverState.normal:    return '정상';
      case DriverState.drowsy:    return '졸음';
      case DriverState.collapsed: return '위험';
    }
  }
}

class DrowsyDetector {
  // ── 임계값 (파이썬 18_state_machine.py 와 동일) ───────────────
  final double earThreshold;       // EAR_THRESHOLD     = 0.25
  final double drowsySeconds;      // DROWSY_SECONDS    = 3.0
  final double tiltThresholdDeg;   // TILT_THRESHOLD    = 30.0
  final double missingSeconds;     // MISSING_SECONDS   = 2.0
  final double dropRatio;          // DROP_RATIO        = 0.25

  DrowsyDetector({
    this.earThreshold     = 0.25,
    this.drowsySeconds    = 3.0,
    this.tiltThresholdDeg = 30.0,
    this.missingSeconds   = 2.0,
    this.dropRatio        = 0.25,
  });

  // ── 내부 상태 (파이썬의 메인 루프 변수와 1:1 대응) ─────────────
  DateTime? _eyeClosedStart;     // eye_closed_start
  DateTime? _faceMissingStart;   // face_missing_start
  double?   _prevFaceY;          // prev_face_y

  // 마지막 프레임 결과 (디버그/UI 표시용)
  double lastEar = 1.0;
  double lastTiltDeg = 0.0;
  bool   lastFaceDetected = false;

  // ── 두 점 사이 유클리드 거리 (파이썬 distance 함수) ───────────
  double _dist(Point<int> a, Point<int> b) {
    final dx = (a.x - b.x).toDouble();
    final dy = (a.y - b.y).toDouble();
    return sqrt(dx * dx + dy * dy);
  }

  // ── EAR 계산 (파이썬 calculate_ear 와 동일한 공식) ─────────────
  //
  //         세로1 + 세로2
  //  EAR = ────────────────
  //         2 × 가로
  //
  // ML Kit FaceContour 의 눈 윤곽 점 16개에서:
  //   - 가로 : 가장 왼쪽 점 ↔ 가장 오른쪽 점
  //   - 세로1 : 가로 1/3 지점의 위/아래 점 거리
  //   - 세로2 : 가로 2/3 지점의 위/아래 점 거리
  // 이 방식으로 파이썬 6랜드마크 EAR 와 같은 의미의 비율을 얻는다.
  double _calculateEar(List<Point<int>> contour) {
    if (contour.length < 4) return 1.0;

    // x 좌표 기준 정렬 → 가로 양 끝점 확보
    final byX = List<Point<int>>.from(contour)
      ..sort((a, b) => a.x.compareTo(b.x));
    final left  = byX.first;
    final right = byX.last;
    final horizontal = _dist(left, right);
    if (horizontal == 0) return 1.0;

    // 가로 1/3, 2/3 지점 x 좌표
    final x1 = left.x + (right.x - left.x) * 1 ~/ 3;
    final x2 = left.x + (right.x - left.x) * 2 ~/ 3;

    // 위쪽 점 / 아래쪽 점 분리 (수평선 대비 위는 y가 작음)
    final midY = (left.y + right.y) / 2;
    final upper = contour.where((p) => p.y < midY).toList();
    final lower = contour.where((p) => p.y > midY).toList();
    if (upper.isEmpty || lower.isEmpty) return 1.0;

    // 가장 가까운 x 위치의 위/아래 점을 골라서 세로 거리 계산
    Point<int> nearestX(List<Point<int>> list, int targetX) {
      list.sort((a, b) => (a.x - targetX).abs().compareTo((b.x - targetX).abs()));
      return list.first;
    }

    final v1 = _dist(nearestX(upper, x1), nearestX(lower, x1));
    final v2 = _dist(nearestX(upper, x2), nearestX(lower, x2));

    return (v1 + v2) / (2.0 * horizontal);
  }

  // ── 양쪽 눈 평균 EAR 만 계산 (상태머신 부작용 없음) ────────────
  // 민감도 자동 보정 화면에서 사용한다.
  //   - 얼굴/눈 윤곽이 없으면 null 반환 (샘플에서 제외)
  //   - update() 와 달리 내부 타이머·이전 위치를 건드리지 않는다.
  double? computeEar(Face? face) {
    if (face == null) return null;
    final leftContour  = face.contours[FaceContourType.leftEye]?.points ?? [];
    final rightContour = face.contours[FaceContourType.rightEye]?.points ?? [];
    if (leftContour.isEmpty || rightContour.isEmpty) return null;
    final earL = _calculateEar(leftContour);
    final earR = _calculateEar(rightContour);
    return (earL + earR) / 2.0;
  }

  // ── 상태 머신 (파이썬 check_state 와 동일한 로직) ──────────────
  DriverState update(Face? face) {
    final now = DateTime.now();
    lastFaceDetected = face != null;

    // 1단계: 얼굴이 보이지 않을 때
    if (face == null) {
      _faceMissingStart ??= now;
      _eyeClosedStart = null;
      lastEar = 0.0;
      lastTiltDeg = 0.0;
      // 일정 시간 지속되면 쓰러짐으로 본다
      if (now.difference(_faceMissingStart!).inMilliseconds >=
          (missingSeconds * 1000)) {
        return DriverState.collapsed;
      }
      return DriverState.normal;
    }

    // 얼굴이 다시 보이면 사라짐 타이머 리셋
    _faceMissingStart = null;

    // EAR 계산 (양쪽 눈 평균)
    final leftContour  = face.contours[FaceContourType.leftEye]?.points ?? [];
    final rightContour = face.contours[FaceContourType.rightEye]?.points ?? [];
    final earL = _calculateEar(leftContour);
    final earR = _calculateEar(rightContour);
    lastEar = (earL + earR) / 2.0;

    // 고개 기울기 (Z축 회전 = 좌우 기울기, 파이썬 face_tilt_angle 대응)
    lastTiltDeg = face.headEulerAngleZ ?? 0.0;

    // 얼굴 위치 (Y 좌표) — 얼굴 자체 높이를 기준으로 정규화
    //   같은 화면에서 카메라 해상도와 얼굴 크기가 다양하므로
    //   '얼굴 박스 높이'를 1.0 단위로 삼아 상대 변화량을 잰다.
    final box = face.boundingBox;
    final faceY = box.height > 0 ? box.center.dy / box.height : 0.0;

    // 2단계: 쓰러짐 감지 (3가지 중 하나라도 해당)
    //   (1) 한 프레임 사이 얼굴이 '아래로' dropRatio 만큼 떨어짐
    //       → 앞으로 고꾸라짐 (DROP_RATIO = 0.25)
    //   화면 좌표는 아래로 갈수록 y가 커지므로, (현재 - 직전)이 양수면
    //   얼굴이 아래로 내려간 것이다. 위로 올라가는 움직임(음수)은 무시한다.
    //   → 얼굴을 위아래로 흔드는 정도로는 발동하지 않고, 실제로 푹 수그릴
    //     때만 잡는다.
    if (_prevFaceY != null && (faceY - _prevFaceY!) > dropRatio) {
      _prevFaceY = faceY;
      return DriverState.collapsed;
    }
    _prevFaceY = faceY;

    //   (2) 고개가 30° 이상 기울어짐 → 옆으로 쓰러짐
    if (lastTiltDeg.abs() > tiltThresholdDeg) {
      return DriverState.collapsed;
    }

    // 3단계: 졸음 감지
    if (lastEar < earThreshold) {
      _eyeClosedStart ??= now;
      final closedMs = now.difference(_eyeClosedStart!).inMilliseconds;
      if (closedMs >= drowsySeconds * 1000) {
        return DriverState.drowsy;
      }
    } else {
      _eyeClosedStart = null;
    }

    return DriverState.normal;
  }

  // 화면 전환 시 상태 초기화
  void reset() {
    _eyeClosedStart = null;
    _faceMissingStart = null;
    _prevFaceY = null;
    lastEar = 1.0;
    lastTiltDeg = 0.0;
    lastFaceDetected = false;
  }
}
