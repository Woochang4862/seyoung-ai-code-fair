import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/drowsy_detector.dart';
import '../services/speed_service.dart';
import '../services/storage.dart';
import '../utils/face_image_converter.dart';

// 카메라로 운전자 얼굴을 실시간 분석해서
//   NORMAL (정상) / DROWSY (졸음) / COLLAPSED (쓰러짐)
// 3가지 상태를 판정한다.
//
// 알고리즘 본체는 services/drowsy_detector.dart 에 분리되어 있고,
// 이 파일은 카메라 → 얼굴 검출 → 상태기 → UI 렌더링 만 담당한다.
//
// 파이썬 원본: 07-ai-python/18_state_machine.py
class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  CameraController? _cameraController;
  CameraDescription? _camera;
  late final FaceDetector _faceDetector;
  final AudioPlayer _audioPlayer = AudioPlayer();
  // 권한 체크 전 build()가 먼저 호출돼도 안전하도록 즉시 초기화
  // (실제 사용자 임계값은 _initialize 안에서 새 인스턴스로 교체)
  DrowsyDetector _detector = DrowsyDetector();

  bool _isProcessing = false;
  bool _isCameraReady = false;
  String _initStatus = '카메라 준비 중...';

  bool _soundOn = true;

  // ── 실험 기능: GPS 정지 게이팅 ───────────────────────────────
  // 켜져 있고 버스가 멈춰 있으면(정류장·신호) 졸음 경고를 울리지 않는다.
  bool _gpsGating = false;
  SpeedService? _speedService;

  // ── 기사 얼굴 선택 (뒤 승객 구분) ────────────────────────────
  // 화면 면적의 이 비율 미만으로 작은 얼굴은 '멀리 있는 승객'으로 보고
  // 기사로 인정하지 않는다. (거치 거리에 따라 조정 필요 — 디버그 표시 참고)
  static const double _minDriverAreaRatio = 0.04;
  double _driverSizeRatio = 0.0; // 현재 기사 후보 얼굴의 화면 대비 면적(디버그용)

  // 마지막 판정 결과 (UI 갱신용)
  DriverState _state = DriverState.normal;

  @override
  void initState() {
    super.initState();
    // 감지 화면에 있는 동안 화면이 꺼지지 않게 한다.
    // (운전 중 화면이 꺼지면 카메라·졸음 감지가 멈추므로)
    WakelockPlus.enable();
    // ML Kit 얼굴 검출기 초기화
    //   enableContours: 눈 윤곽 16개 점 추출 (EAR 계산용)
    //   enableClassification: 눈 열림 확률·미소 확률 (보조 지표)
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableClassification: true,
        performanceMode: FaceDetectorMode.fast,
        // 작은 얼굴(먼 승객·노이즈)을 ML Kit 단계에서 걸러낸다.
        //   - ML Kit 은 '가장 두드러진 얼굴 1개'에만 눈 윤곽을 계산한다.
        //     주변에 작은 얼굴이 끼면 기사 얼굴의 윤곽이 빠져 EAR 이 1.0(눈 뜸)
        //     으로 잘못 나와 졸음 감지가 안 되는 문제가 있었다.
        //   - 얼굴 너비가 화면 너비의 15% 이상인 가까운 얼굴(=기사)만 잡으면
        //     기사 얼굴이 거의 단독으로 잡혀 윤곽이 안정적으로 나온다.
        minFaceSize: 0.15,
      ),
    );
    _initialize();
  }

  Future<void> _initialize() async {
    // 0) 오디오 세션 설정 — iOS 무음 모드여도 경고음이 들리도록
    await _audioPlayer.setAudioContext(AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
      android: const AudioContextAndroid(
        usageType: AndroidUsageType.alarm,
        contentType: AndroidContentType.sonification,
      ),
    ));

    // 1) 저장된 설정 불러오기 (민감도/소리/GPS)
    final threshold = await Storage.loadThreshold();
    _soundOn = await Storage.loadSoundOn();
    _gpsGating = await Storage.loadGpsGating();

    // 파이썬 18_state_machine.py 의 임계값을 그대로 사용.
    // 단 EAR_THRESHOLD 만 사용자 설정값(슬라이더)을 반영한다.
    _detector = DrowsyDetector(earThreshold: threshold);

    // 1-1) 실험 기능: GPS 정지 게이팅이 켜져 있으면 속도 모니터 시작
    if (_gpsGating) {
      final stationarySpeed = await Storage.loadStationarySpeed();
      _speedService = SpeedService(
        stationarySpeedKmh: stationarySpeed,
        onUpdate: () {
          // 정지→출발 등 속도 상태가 바뀔 때 화면(속도 배지)을 갱신
          if (mounted) setState(() {});
        },
      );
      await _speedService!.start();
    }

    // 2) 카메라 권한 요청
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _initStatus = status.isPermanentlyDenied
              ? '카메라 권한 거부됨 — 설정에서 허용해주세요'
              : '카메라 권한이 필요합니다';
        });
        if (status.isPermanentlyDenied) _showSettingsDialog();
      }
      return;
    }

    // 3) 전면 카메라 초기화
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (mounted) setState(() => _initStatus = '카메라를 찾을 수 없습니다');
      return;
    }
    _camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      _camera!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await _cameraController!.initialize();
    if (!mounted) return;
    setState(() => _isCameraReady = true);

    // 4) 매 프레임 콜백 등록
    await _cameraController!.startImageStream(_onCameraFrame);
  }

  // 여러 얼굴 중 '기사' 얼굴을 고른다.
  //   - 기사 = 카메라(거치 폰)에 가장 가까운 사람 = 화면에서 가장 큰 얼굴
  //   - 뒤 승객은 멀어서 작게 잡힌다.
  //   - 가장 큰 얼굴조차 화면 면적의 _minDriverAreaRatio 미만이면
  //     '기사 없음(null)'으로 본다. → 기사가 쓰러져 사라지고 뒤 승객만
  //     보이는 경우, 작은 승객은 기사로 인정되지 않아 쓰러짐 감지가 작동.
  //   - 면적으로 비교하므로 카메라 회전(가로/세로)과 무관하다.
  Face? _pickDriverFace(List<Face> faces, int imageWidth, int imageHeight) {
    if (faces.isEmpty) {
      _driverSizeRatio = 0.0;
      return null;
    }

    // 면적이 가장 큰 얼굴 찾기
    Face biggest = faces.first;
    double biggestArea =
        biggest.boundingBox.width * biggest.boundingBox.height;
    for (final f in faces.skip(1)) {
      final area = f.boundingBox.width * f.boundingBox.height;
      if (area > biggestArea) {
        biggest = f;
        biggestArea = area;
      }
    }

    // 화면 대비 얼굴 면적 비율
    final imageArea = (imageWidth * imageHeight).toDouble();
    _driverSizeRatio = imageArea > 0 ? biggestArea / imageArea : 0.0;

    // 기사라고 보기엔 너무 작으면(멀리 있는 승객뿐) 기사 없음 처리
    if (_driverSizeRatio < _minDriverAreaRatio) return null;
    return biggest;
  }

  // 카메라가 새 프레임을 줄 때마다 호출 (≈30fps)
  Future<void> _onCameraFrame(CameraImage image) async {
    if (_isProcessing) return; // 이전 프레임이 아직 처리 중이면 스킵
    _isProcessing = true;

    try {
      final input = toInputImage(image, _camera!);
      if (input == null) return;

      final faces = await _faceDetector.processImage(input);
      // 뒤 승객이 아니라 '기사' 얼굴만 고른다 (가장 큰 얼굴 + 최소 크기).
      // 기사로 볼 만한 얼굴이 없으면 null → 기존 '얼굴 사라짐 → 쓰러짐' 작동.
      final face = _pickDriverFace(faces, image.width, image.height);

      // 알고리즘 본체에 위임 → 새 상태 반환
      var newState = _detector.update(face);

      // 실험 기능: GPS 정지 게이팅 ────────────────────────────────
      // 버스가 멈춰 있으면(정류장·신호 대기) 졸음/위험 판정을 무시하고
      // '정상'으로 둔다. 정차 중 잠깐 눈을 감거나 고개를 숙여도
      // 경고가 울리지 않게 하기 위함. (출발하면 자동으로 다시 감지)
      final stationary = _gpsGating &&
          _speedService != null &&
          !_speedService!.isMoving;
      if (stationary) {
        newState = DriverState.normal;
      }

      // 상태 전환 처리
      //   - 비정상 상태로 진입 → 알림 시작 (사운드 무한반복)
      //   - 비정상 → 비정상 (DROWSY ↔ COLLAPSED 등 변경) → 사운드 교체
      //   - 정상으로 복귀 → 사운드 정지
      if (newState != _state) {
        if (newState == DriverState.normal) {
          await _stopAlert();
        } else {
          await _triggerAlert(newState);
        }
      }

      if (mounted && newState != _state) {
        setState(() => _state = newState);
      } else if (mounted) {
        // EAR/기울기 디버그 표시 갱신용
        setState(() {});
      }
    } catch (_) {
      // 한 프레임 실패는 무시
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _triggerAlert(DriverState state) async {
    // 기록 저장 (위험 상태 진입/전환 1회만)
    await Storage.addEvent(DrowsyEvent(
      time: DateTime.now(),
      leftEyeOpen: _detector.lastEar,
      rightEyeOpen: _detector.lastEar,
    ));

    // 햅틱 피드백 — 진입 시점 1회 강하게
    //   DROWSY     → 한 번 강한 진동
    //   COLLAPSED  → 두 번 강한 진동 (긴급)
    if (state == DriverState.drowsy) {
      HapticFeedback.heavyImpact();
    } else if (state == DriverState.collapsed) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 200),
          () => HapticFeedback.heavyImpact());
    }

    // 사운드 — 위험 상태가 끝날 때까지 무한 반복 재생
    //   DROWSY     → alert.wav (단일 비프 반복)
    //   COLLAPSED  → danger.wav (3연속 비프 반복)
    if (_soundOn) {
      try {
        final asset = state == DriverState.collapsed
            ? 'sounds/danger.wav'
            : 'sounds/alert.wav';
        await _audioPlayer.stop();
        await _audioPlayer.setReleaseMode(ReleaseMode.loop); // 무한 반복
        await _audioPlayer.play(AssetSource(asset));
      } catch (_) {/* 자산 없으면 무음 */}
    }
  }

  // 위험 상태에서 정상으로 복귀할 때 호출 — 사운드 정지
  Future<void> _stopAlert() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {/* 무시 */}
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('카메라 권한 필요'),
        content: const Text(
          '졸음 감지를 위해 카메라 권한이 필요합니다.\n'
          '설정에서 카메라 접근을 허용해주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('설정 열기'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
    _audioPlayer.dispose();
    _speedService?.stop();
    // 감지 화면을 벗어나면 화면 꺼짐 방지 해제 (배터리 절약)
    WakelockPlus.disable();
    super.dispose();
  }

  // ── UI ──────────────────────────────────────────────────────────

  Color _stateColor(DriverState s) {
    switch (s) {
      case DriverState.normal:    return Colors.green;
      case DriverState.drowsy:    return Colors.amber;
      case DriverState.collapsed: return Colors.red;
    }
  }

  String _stateText(DriverState s) {
    switch (s) {
      case DriverState.normal:    return '✓ 정상 운행 중';
      case DriverState.drowsy:    return '⚠ 졸음 감지!';
      case DriverState.collapsed: return '🚨 위험! 쓰러짐 감지';
    }
  }

  // 실험 기능: GPS 속도/정지 상태 배지
  //   GPS 못 씀 → 회색 "GPS 없음" (감지는 평소대로 동작)
  //   정지 중   → 주황 "정지 중 · 감지 일시정지"
  //   운행 중   → 파랑 "주행 12km/h"
  Widget _buildGpsBadge() {
    final svc = _speedService;
    late final Color color;
    late final String text;
    if (svc == null || !svc.available) {
      color = Colors.grey;
      text = '📡 GPS 없음';
    } else if (!svc.isMoving) {
      color = Colors.orange;
      text = '⏸ 정지 중 · 감지 일시정지';
    } else {
      color = Colors.blue;
      text = '🚌 주행 ${svc.speedKmh.toStringAsFixed(0)}km/h';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('감지 화면'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // ── 카메라 미리보기 (비율 보존) ─────────────────────────
          Positioned.fill(
            child: _isCameraReady && _cameraController != null
                ? Center(
                    child: AspectRatio(
                      aspectRatio: 1 / _cameraController!.value.aspectRatio,
                      child: CameraPreview(_cameraController!),
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(_initStatus),
                      ],
                    ),
                  ),
          ),

          // ── 위험/졸음 상태 시 화면 테두리 ───────────────────────
          if (_state != DriverState.normal)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: _stateColor(_state), width: 12),
                  ),
                ),
              ),
            ),

          // ── 상단 디버그 (EAR / 기울기 / 얼굴 검출) ──────────────
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '얼굴 ${_detector.lastFaceDetected ? "✓" : "✗"}   '
                'EAR ${_detector.lastEar.toStringAsFixed(2)}   '
                '눈뜸 ${_detector.lastEyeOpenProb == null ? "-" : _detector.lastEyeOpenProb!.toStringAsFixed(2)}'
                '${_detector.lastUsedProb ? "*" : ""}   '
                '기울기 ${_detector.lastTiltDeg.toStringAsFixed(1)}°   '
                '크기 ${(_driverSizeRatio * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),

          // ── 실험 기능: GPS 속도/정지 배지 ───────────────────────
          if (_gpsGating)
            Positioned(
              left: 16,
              top: 56,
              child: _buildGpsBadge(),
            ),

          // ── 하단 큰 상태 라벨 ──────────────────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _stateColor(_state).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _stateText(_state),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
