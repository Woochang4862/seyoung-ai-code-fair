# 06. 한국코드페어 프로젝트

**접수 마감**: 2026.05.25

## 프로젝트 개요
**버스 운전기사 위험상황 인지 대응 시스템**
카메라 + AI(티쳐블 머신) 기반으로 운전기사의 졸음/위험 상황을 감지하는 앱

## 기술 스택
- **AI**: Teachable Machine (눈 감기 감지 모델)
- **언어/프레임워크**: Python (AI 모델 연동), Flutter (모바일 앱 UI)
- **플랫폼**: Android/iOS

## 개발 일정 (약 6주)
| 주차 | 목표 |
|------|------|
| 1~2 | Flutter 기초 (프로필 카드, StatefulWidget) |
| 3 | 카메라 화면 구현, 기본 UI 구성 |
| 4 | AI 모델 연동 (눈 감기 감지) |
| 5 | 알림/경고 기능, UX 개선 |
| 6 | 테스트, 발표 자료 준비, 제출 |

## 할 일
- [ ] 앱에 필요한 화면 2~3개 스케치 (종이도 OK)
- [ ] 메인 화면 레이아웃 구상
- [ ] AI 모델 연결 방식 조사
- [ ] 발표 자료 아이디어 정리

## 실험 기능 (experimental-feature 브랜치)
아직 정식 기능이 아니라 실험 단계로 추가한 두 가지 기능.

### 1. 민감도 자동 보정
사람마다 눈 크기·눈매가 달라서 졸음 판정 기준(EAR 임계값)도 달라야 한다.
설정 → **민감도 자동 보정 (실험)** 에서 카메라로 직접 측정한다.
1. 눈을 크게 뜨고 정면 보기 → 뜬 눈 EAR 평균 측정
2. 눈을 감기 → 감은 눈 EAR 평균 측정
3. 두 값의 중간을 임계값으로 자동 계산해 저장
   `threshold = (뜬눈EAR + 감은눈EAR) / 2`
- 관련 코드: `lib/screens/calibration_screen.dart`,
  `DrowsyDetector.computeEar()`

### 2. GPS 정지 시 감지 끄기
정류장 정차·신호 대기처럼 버스가 멈춰 있을 땐 기사가 잠깐 눈을 감거나
고개를 숙여도 위험하지 않다. GPS 속도가 설정값(기본 5km/h) 미만이면
'정지'로 보고 졸음 경고를 울리지 않는다. 출발하면 자동으로 다시 감지.
- 설정 → **실험 기능 → 정지 시 감지 끄기 (GPS)** 로 켜고,
  '정지 판단 속도'를 조절할 수 있다.
- 관련 코드: `lib/services/speed_service.dart`,
  `DetectionScreen` 의 GPS 게이팅 로직
- 추가 패키지: `geolocator`, 위치 권한(Android/iOS 매니페스트)

> ⚠️ GPS 신호를 못 받으면(터널·실내) 안전하게 '움직임'으로 보고
> 졸음 감지를 계속 켜 둔다. GPS 고장으로 감지가 통째로 꺼지는 것을 막기 위함.

## 참고 자료
- Teachable Machine: https://teachablemachine.withgoogle.com/
- Flutter 카메라 패키지: `camera` (pub.dev)
- GPS 속도: `geolocator` (pub.dev)
