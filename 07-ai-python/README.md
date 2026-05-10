# 07. AI Python — 한국코드페어 AI 엔진

버스 운전기사 위험상황 인지 시스템의 Python AI 파트입니다.

## 환경 세팅 (처음 한 번만)

```bash
# 의존성 설치 (pyproject.toml 기반)
poetry install

# 가상환경 진입
poetry shell
```

> Python 3.12.8 + Poetry 사용. `.venv` 폴더가 자동 생성됩니다.

## 수업별 파일

| 파일 | 회차 | 내용 |
|------|------|------|
| `14_landmark_intro.py` | 14회차 | MediaPipe 입문 — 얼굴 랜드마크 추출 |
| `16_ear_algorithm.py`  | 16회차 | EAR 알고리즘 — 눈 감김 감지 |
| `18_state_machine.py`  | 18회차 | 상태 머신 — 졸음 + 쓰러짐 통합 MVP |
| `19_alert_sound.py`    | 19회차 | 음성/효과음 경고 — `say` + `afplay` |
| `alert.py`             | (헬퍼) | 비동기 사운드 재생 + 스팸 차단 모듈 |

## 실행 방법

```bash
# 가상환경 안에서
poetry run python 14_landmark_intro.py
poetry run python 16_ear_algorithm.py
poetry run python 18_state_machine.py

# 웹캠 화면이 켜지면 q 키로 종료
```

## 설치된 패키지

| 패키지 | 버전 | 용도 |
|--------|------|------|
| mediapipe | ≥0.10.30 | 얼굴 468개 랜드마크 추출 |
| opencv-python | ≥4.10 | 웹캠 입력 + 화면 출력 |
| numpy | ≥1.24, <2.0 | 수치 계산 |
