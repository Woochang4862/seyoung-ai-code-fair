import 'dart:io' show Platform;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart' show Size;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// 카메라가 주는 CameraImage를 ML Kit이 받을 수 있는 InputImage로 변환한다.
//
// 플랫폼마다 픽셀 형식이 달라서 분기가 필요하다:
//   - Android : NV21 (단일 plane)
//   - iOS     : BGRA8888 (단일 plane)
//
// 변환에 실패하면 null을 돌려준다 (해당 프레임은 건너뛴다).
InputImage? toInputImage(CameraImage image, CameraDescription camera) {
  // 1) 카메라 회전값 → ML Kit이 이해하는 회전값으로
  final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
  if (rotation == null) return null;

  // 2) 픽셀 포맷
  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null) return null;

  // 3) 플랫폼별 허용 포맷만 통과
  if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
  if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
  if (image.planes.length != 1) return null;

  final plane = image.planes.first;
  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}
