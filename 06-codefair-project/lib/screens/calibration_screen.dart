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
//   1단계) 눈을 "크게 뜨고" 정면을 본다  → 뜬 눈 EAR 평균(earOpen)
//   2단계) 눈을 "감는다"               → 감은 눈 EAR 평균(earClosed)
//   결과)  두 값의 중간을 임계값으로 삼는다
//          threshold = (earOpen + earClosed) / 2
//        → 이 사람 기준으로 '딱 절반쯤 감았을 때'를 경계선으로 잡는 셈.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

// 보정 진행 단계
enum _Phase {
  intro,         // 시작 안내
  measuringOpen, // 눈 뜬 상태 측정 중
  measuringClosed, // 눈 감은 상태 측정 중
  result,        // 결과 표시
  failed,        // 실패(권한·측정 부족)
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

  // 한 단계당 모을 EAR 샘플 (측정 중에만 채워짐)
  final List<double> _samples = [];
  static const int _samplesNeeded = 30; // 약 1~2초 분량

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

  // 매 프레임 EAR 계산 — 측정 중인 단계에서만 샘플을 모은다.
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
      if (ear == null) return; // 얼굴/눈을 못 찾은 프레임은 건너뜀

      _samples.add(ear);
      if (mounted) setState(() {}); // 진행률 갱신
      if (_samples.length >= _samplesNeeded) {
        _finishCurrentPhase();
      }
    } catch (_) {
      // 한 프레임 실패는 무시
    } finally {
      _isProcessing = false;
    }
  }

  // 모은 샘플의 평균을 구해 현재 단계를 마무리한다.
  void _finishCurrentPhase() {
    final avg = _samples.reduce((a, b) => a + b) / _samples.length;
    if (_phase == _Phase.measuringOpen) {
      _earOpen = avg;
      _samples.clear();
      setState(() => _phase = _Phase.measuringClosed);
    } else if (_phase == _Phase.measuringClosed) {
      _earClosed = avg;
      _samples.clear();
      _computeResult();
    }
  }

  // 뜬 눈/감은 눈 평균으로 임계값을 계산한다.
  void _computeResult() {
    // 뜬 눈이 감은 눈보다 충분히 커야 측정이 믿을 만하다.
    // 차이가 너무 작으면(0.05 미만) 측정이 잘못된 것 → 다시 하도록 안내.
    if (_earOpen - _earClosed < 0.05) {
      setState(() {
        _phase = _Phase.failed;
        _status = '눈 뜸/감음 차이가 너무 작아요.\n밝은 곳에서 다시 시도해주세요.';
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
    _samples.clear();
    setState(() {
      _earOpen = 0.0;
      _earClosed = 0.0;
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
          // 카메라 미리보기
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

          // 어둡게 깔고 안내 카드 표시
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: _buildOverlay(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    switch (_phase) {
      case _Phase.intro:
        return _card(
          icon: Icons.face_retouching_natural,
          title: '내 눈에 맞는 민감도 찾기',
          body: '두 단계로 측정합니다.\n'
              '① 눈을 크게 뜨고 정면 보기\n'
              '② 눈을 감기\n\n'
              '얼굴이 화면에 잘 보이는 밝은 곳에서 진행하세요.',
          buttonLabel: '시작',
          onPressed: () => setState(() => _phase = _Phase.measuringOpen),
        );

      case _Phase.measuringOpen:
        return _measuringCard(
          title: '① 눈을 크게 뜨세요',
          hint: '정면을 보고 눈을 크게 뜬 채 기다리세요',
        );

      case _Phase.measuringClosed:
        return _measuringCard(
          title: '② 눈을 감으세요',
          hint: '편하게 눈을 감고 기다리세요',
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
    }
  }

  // 측정 중 카드 (진행률 표시)
  Widget _measuringCard({required String title, required String hint}) {
    final progress = (_samples.length / _samplesNeeded).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 20),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text('${(progress * 100).toInt()}%  측정 중...',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ],
      ),
    );
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
