import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/drowsy_detector.dart';
import '../services/storage.dart';
import '../utils/face_image_converter.dart';

// 민감도 자동 보정 화면 (experimental-feature)
// ─────────────────────────────────────────────────────────
// 사람마다 눈 크기·눈매가 달라서 졸음 판정 기준(EAR 임계값)도 달라야 한다.
// 고정값 0.25 는 어떤 사람에겐 너무 둔감하고, 어떤 사람에겐 너무 예민하다.
//
// 이 화면은 카메라로 직접 그 사람의 눈을 측정해서 가장 알맞은 임계값을 찾는다:
//   1단계) 눈을 "크게 뜨고" 정면을 본다  → 뜬 눈 EAR(earOpen)
//   2단계) 눈을 "감는다"               → 감은 눈 EAR(earClosed)
//   결과)  두 값의 중간을 임계값으로 삼는다
//          threshold = (earOpen + earClosed) / 2
//        → 이 사람 기준으로 '딱 절반쯤 감았을 때'를 경계선으로 잡는 셈.
//
// [측정 방식 — 수동]
//   카메라가 가려지지 않게 화면을 띄워 두고, 자세를 잡은 다음
//   "측정하기" 버튼(또는 화면 아무 곳이나 탭)을 누르면 그 순간의 EAR 을 잡는다.
//   값이 흔들리지 않도록 직전 몇 프레임의 평균을 쓴다.
//   → 눈을 감은 상태(2단계)에서도 화면 아무 데나 톡 누르면 측정된다.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

// 보정 진행 단계
enum _Phase {
  intro,           // 시작 안내
  measuringOpen,   // 눈 뜬 상태 측정
  measuringClosed, // 눈 감은 상태 측정
  result,          // 결과 표시
  failed,          // 실패(권한·측정 부족)
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  CameraController? _cameraController;
  CameraDescription? _camera;
  late final FaceDetector _faceDetector;
  // EAR 계산식을 그대로 쓰기 위해 detector 의 computeEar 를 빌려 쓴다.
  final DrowsyDetector _detector = DrowsyDetector();

  bool _isProcessing = false;
  bool _isCameraReady = false;

  _Phase _phase = _Phase.intro;
  String _status = '카메라 준비 중...';

  // 직전 몇 프레임의 EAR 을 모아 두는 짧은 버퍼.
  // 탭하는 순간 이 값들의 평균을 측정값으로 쓴다(값 떨림 방지).
  final List<double> _recentEars = [];
  static const int _bufferSize = 8; // 약 0.3초 분량
  double? _liveEar; // 화면에 보여줄 실시간 EAR (얼굴 없으면 null)

  double _earOpen = 0.0;   // 1단계 결과
  double _earClosed = 0.0; // 2단계 결과
  double _result = 0.25;   // 계산된 임계값

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _status = '카메라 권한이 필요합니다';
        });
      }
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _status = '카메라를 찾을 수 없습니다';
        });
      }
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
    await _cameraController!.startImageStream(_onFrame);
  }

  // 매 프레임 EAR 계산 — 측정 단계에서 실시간 값/버퍼만 갱신한다.
  // (자동으로 넘어가지 않는다. 사용자가 탭할 때만 측정 확정.)
  Future<void> _onFrame(CameraImage image) async {
    if (_isProcessing) return;
    if (_phase != _Phase.measuringOpen && _phase != _Phase.measuringClosed) {
      return; // 안내/결과 화면에서는 계산 안 함
    }
    _isProcessing = true;
    try {
      final input = toInputImage(image, _camera!);
      if (input == null) return;
      final faces = await _faceDetector.processImage(input);
      final face = faces.isEmpty ? null : faces.first;
      final ear = _detector.computeEar(face);

      if (ear == null) {
        // 얼굴/눈을 못 찾은 프레임 → 실시간 표시만 비우고 버퍼는 유지
        if (mounted) setState(() => _liveEar = null);
        return;
      }

      _recentEars.add(ear);
      if (_recentEars.length > _bufferSize) _recentEars.removeAt(0);
      if (mounted) setState(() => _liveEar = ear);
    } catch (_) {
      // 한 프레임 실패는 무시
    } finally {
      _isProcessing = false;
    }
  }

  // 탭/버튼 → 지금 버퍼의 평균을 이 단계 측정값으로 확정한다.
  void _capture() {
    if (_phase != _Phase.measuringOpen && _phase != _Phase.measuringClosed) {
      return;
    }
    // 최소 몇 프레임은 모여 있어야 한다 (얼굴이 안 잡히면 막음)
    if (_recentEars.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('얼굴이 잘 안 보여요. 카메라에 얼굴을 맞추고 다시 눌러주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final avg = _recentEars.reduce((a, b) => a + b) / _recentEars.length;

    if (_phase == _Phase.measuringOpen) {
      _earOpen = avg;
      _recentEars.clear(); // 다음 단계(눈 감기)를 위해 버퍼 비움
      setState(() => _phase = _Phase.measuringClosed);
    } else {
      _earClosed = avg;
      _recentEars.clear();
      _computeResult();
    }
  }

  // 뜬 눈/감은 눈 측정값으로 임계값을 계산한다.
  void _computeResult() {
    // 뜬 눈이 감은 눈보다 충분히 커야 측정이 믿을 만하다.
    // 차이가 너무 작으면(0.05 미만) 측정이 잘못된 것 → 다시 하도록 안내.
    if (_earOpen - _earClosed < 0.05) {
      setState(() {
        _phase = _Phase.failed;
        _status = '눈 뜸/감음 차이가 너무 작아요.\n'
            '1단계에선 눈을 크게, 2단계에선 확실히 감고\n'
            '밝은 곳에서 다시 시도해주세요.';
      });
      return;
    }
    // 두 값의 중간을 경계선으로. 슬라이더 범위(0.10~0.40)로 안전하게 자른다.
    final mid = (_earOpen + _earClosed) / 2.0;
    _result = mid.clamp(0.10, 0.40);
    setState(() => _phase = _Phase.result);
  }

  Future<void> _save() async {
    await Storage.saveThreshold(_result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('민감도 ${_result.toStringAsFixed(2)} 저장 완료')),
    );
    Navigator.pop(context);
  }

  // 처음부터 다시
  void _restart() {
    _recentEars.clear();
    setState(() {
      _earOpen = 0.0;
      _earClosed = 0.0;
      _liveEar = null;
      _phase = _Phase.intro;
    });
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  // ── UI ──────────────────────────────────────────────────────────
  bool get _isMeasuring =>
      _phase == _Phase.measuringOpen || _phase == _Phase.measuringClosed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('민감도 자동 보정'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // 카메라 미리보기 (항상 깔려 있음)
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
                        Text(_status),
                      ],
                    ),
                  ),
          ),

          // 측정 단계: 카메라를 가리지 않는 얇은 안내 바 + 측정 버튼
          if (_isMeasuring) _buildMeasuringLayer(),

          // 그 외 단계(안내/결과/실패): 어둡게 깔고 카드 표시
          if (!_isMeasuring)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.45),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: _buildCard(),
              ),
            ),
        ],
      ),
    );
  }

  // 측정 중 레이어 — 카메라가 보이도록 위/아래에만 반투명 바를 둔다.
  // 화면 전체가 탭 영역이라, 눈을 감은 상태에서도 아무 데나 누르면 측정된다.
  Widget _buildMeasuringLayer() {
    final isOpenPhase = _phase == _Phase.measuringOpen;
    final faceOk = _liveEar != null;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // 빈 곳 탭도 받기
        onTap: _capture,
        child: Stack(
          children: [
            // 상단 안내 바
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOpenPhase ? '① 눈을 크게 뜨세요' : '② 눈을 감으세요',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isOpenPhase
                          ? '정면을 보고 눈을 크게 뜬 뒤 아래 버튼을 누르세요'
                          : '눈을 감고 화면 아무 곳이나 톡 누르세요',
                      style: TextStyle(color: Colors.grey[300], fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      faceOk
                          ? '현재 EAR  ${_liveEar!.toStringAsFixed(2)}'
                          : '얼굴을 찾는 중...',
                      style: TextStyle(
                        color: faceOk ? Colors.lightBlueAccent : Colors.orangeAccent,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 하단 측정 버튼 + 안내
            Positioned(
              left: 24,
              right: 24,
              bottom: 28,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton.icon(
                      onPressed: _capture,
                      icon: const Icon(Icons.center_focus_strong),
                      label: Text(
                        isOpenPhase ? '뜬 눈 측정하기' : '감은 눈 측정하기',
                        style: const TextStyle(fontSize: 18),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '버튼 또는 화면 아무 곳이나 누르면 측정됩니다',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 안내/결과/실패 카드
  Widget _buildCard() {
    switch (_phase) {
      case _Phase.intro:
        return _card(
          icon: Icons.face_retouching_natural,
          title: '내 눈에 맞는 민감도 찾기',
          body: '두 단계로 측정합니다.\n'
              '① 눈을 크게 뜨고 측정\n'
              '② 눈을 감고 측정\n\n'
              '각 단계에서 자세를 잡은 뒤\n버튼(또는 화면)을 직접 눌러 측정합니다.\n'
              '밝은 곳에서 진행하세요.',
          buttonLabel: '시작',
          onPressed: () {
            _recentEars.clear();
            setState(() => _phase = _Phase.measuringOpen);
          },
        );

      case _Phase.result:
        return _card(
          icon: Icons.check_circle,
          title: '측정 완료!',
          body: '뜬 눈 EAR: ${_earOpen.toStringAsFixed(2)}\n'
              '감은 눈 EAR: ${_earClosed.toStringAsFixed(2)}\n\n'
              '추천 민감도(임계값)\n'
              '➡  ${_result.toStringAsFixed(2)}',
          buttonLabel: '이 값으로 저장',
          onPressed: _save,
          secondaryLabel: '다시 측정',
          onSecondary: _restart,
        );

      case _Phase.failed:
        return _card(
          icon: Icons.error_outline,
          title: '측정 실패',
          body: _status,
          buttonLabel: '다시 시도',
          onPressed: _restart,
        );

      // 측정 단계는 카드가 아니라 _buildMeasuringLayer 가 담당
      case _Phase.measuringOpen:
      case _Phase.measuringClosed:
        return const SizedBox.shrink();
    }
  }

  // 안내/결과 카드 (버튼 1~2개)
  Widget _card({
    required IconData icon,
    required String title,
    required String body,
    required String buttonLabel,
    required VoidCallback onPressed,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.blue),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[800], fontSize: 15)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(buttonLabel, style: const TextStyle(fontSize: 16)),
            ),
          ),
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
