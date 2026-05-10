"""
18회차: 쓰러짐 감지 + 상태 머신 — Python AI MVP 완성
──────────────────────────────────────────────────────
상태 정의
  NORMAL    — 이상 없음
  DROWSY    — 눈이 3초 이상 감겨 있음
  COLLAPSED — 쓰러지거나 얼굴이 오래 사라짐

쓰러짐 판정 기준 (3가지 중 하나라도 해당)
  1. 얼굴 미감지가 2초 이상 지속
  2. 한 프레임 사이 얼굴 Y 좌표가 급격히 이동 (갑자기 앞으로 쓰러짐)
  3. 고개 기울기가 30도 이상 (옆으로 쓰러짐)
"""

import cv2
import mediapipe as mp
import time
import math
import urllib.request
import os

# ── 모델 파일 자동 다운로드 ─────────────────────────────────────
MODEL_PATH = "face_landmarker.task"
MODEL_URL  = (
    "https://storage.googleapis.com/mediapipe-models/"
    "face_landmarker/face_landmarker/float16/1/face_landmarker.task"
)

def download_model():
    if not os.path.exists(MODEL_PATH):
        print("모델 파일 다운로드 중... (처음 한 번만, 약 30초)")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
        print("다운로드 완료!")

# ── Tasks API ───────────────────────────────────────────────────
BaseOptions          = mp.tasks.BaseOptions
FaceLandmarker       = mp.tasks.vision.FaceLandmarker
FaceLandmarkerOptions = mp.tasks.vision.FaceLandmarkerOptions
RunningMode          = mp.tasks.vision.RunningMode

# ── 랜드마크 번호 ────────────────────────────────────────────────
RIGHT_EYE = [33, 160, 158, 133, 153, 144]
LEFT_EYE  = [362, 385, 387, 263, 373, 380]

# ── 임계값 (직접 조정해보세요) ──────────────────────────────────
EAR_THRESHOLD   = 0.25    # 눈 감김 판정값
DROWSY_SECONDS  = 3.0     # 졸음 판정 지속 시간 (초)
TILT_THRESHOLD  = 30.0    # 고개 기울기 한계 (도)
MISSING_SECONDS = 2.0     # 얼굴 사라짐 한계 (초)
DROP_RATIO      = 0.25    # 얼굴 Y 좌표 급변 비율

# ── 상태 상수 ────────────────────────────────────────────────────
NORMAL    = "NORMAL"
DROWSY    = "DROWSY"
COLLAPSED = "COLLAPSED"

STATE_LABEL = {
    NORMAL:    "✓ 정상",
    DROWSY:    "⚠ 졸음",
    COLLAPSED: "🚨 위험",
}
STATE_COLOR = {
    NORMAL:    (0, 200, 0),
    DROWSY:    (0, 165, 255),
    COLLAPSED: (0, 0, 255),
}


# ── 헬퍼 함수 ────────────────────────────────────────────────────

def distance(p1, p2):
    return ((p1.x - p2.x) ** 2 + (p1.y - p2.y) ** 2) ** 0.5


def calculate_ear(eye):
    return (distance(eye[1], eye[5]) + distance(eye[2], eye[4])) / (2.0 * distance(eye[0], eye[3]))


def get_eye(lm, indices):
    return [lm[i] for i in indices]


def face_tilt_angle(lm):
    """
    오른쪽 눈 끝(33) ↔ 왼쪽 눈 끝(263) 연결선의 기울기를 각도로 반환.
    고개가 오른쪽으로 기울면 양수, 왼쪽이면 음수.
    """
    r = lm[33]
    l = lm[263]
    dx = l.x - r.x
    dy = l.y - r.y
    return math.degrees(math.atan2(dy, dx))


def is_sudden_drop(face_y, prev_y):
    """
    얼굴 Y 좌표가 한 프레임 만에 DROP_RATIO 이상 변하면 True.
    (갑자기 앞으로 쓰러질 때 발생)
    """
    if prev_y is None:
        return False
    return abs(face_y - prev_y) > DROP_RATIO


# ── 상태 머신 ────────────────────────────────────────────────────

def check_state(face_detected, ear, eye_closed_time,
                tilt, face_y, prev_y, face_missing_start):
    """
    현재 프레임 정보로 운전자 상태를 판단.

    Returns
    -------
    state               : NORMAL / DROWSY / COLLAPSED
    face_missing_start  : 업데이트된 얼굴 사라짐 시작 시각
    """
    now = time.time()

    # ── 1단계: 얼굴이 보이지 않을 때 ───────────────────────────
    if not face_detected:
        if face_missing_start is None:
            face_missing_start = now
        elif now - face_missing_start >= MISSING_SECONDS:
            return COLLAPSED, face_missing_start
        return NORMAL, face_missing_start

    # 얼굴이 다시 보이면 타이머 리셋
    face_missing_start = None

    # ── 2단계: 쓰러짐 감지 ──────────────────────────────────────
    if is_sudden_drop(face_y, prev_y):
        return COLLAPSED, face_missing_start
    if abs(tilt) > TILT_THRESHOLD:
        return COLLAPSED, face_missing_start

    # ── 3단계: 졸음 감지 ────────────────────────────────────────
    if ear < EAR_THRESHOLD and eye_closed_time >= DROWSY_SECONDS:
        return DROWSY, face_missing_start

    return NORMAL, face_missing_start


# ── 메인 루프 ────────────────────────────────────────────────────

def main():
    download_model()

    options = FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=RunningMode.VIDEO,
        num_faces=1,
    )

    cap = cv2.VideoCapture(0)

    eye_closed_start   = None
    face_missing_start = None
    prev_face_y        = None
    state              = NORMAL
    timestamp_ms       = 0

    with FaceLandmarker.create_from_options(options) as landmarker:
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            timestamp_ms += 33

            rgb    = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = landmarker.detect_for_video(mp_img, timestamp_ms)

            face_detected   = bool(result.face_landmarks)
            ear             = 0.0
            tilt            = 0.0
            face_y          = prev_face_y
            eye_closed_time = 0.0

            if face_detected:
                lm = result.face_landmarks[0]

                # EAR
                r = get_eye(lm, RIGHT_EYE)
                l = get_eye(lm, LEFT_EYE)
                ear = (calculate_ear(r) + calculate_ear(l)) / 2.0

                # 눈 감김 지속 시간
                if ear < EAR_THRESHOLD:
                    if eye_closed_start is None:
                        eye_closed_start = time.time()
                    eye_closed_time = time.time() - eye_closed_start
                else:
                    eye_closed_start = None
                    eye_closed_time = 0.0

                # 고개 기울기 + 얼굴 Y 위치 (코 끝 기준)
                tilt   = face_tilt_angle(lm)
                face_y = lm[1].y

            # 상태 머신 실행
            state, face_missing_start = check_state(
                face_detected, ear, eye_closed_time,
                tilt, face_y, prev_face_y, face_missing_start,
            )
            prev_face_y = face_y

            # ── 화면 렌더링 ──────────────────────────────────────
            color = STATE_COLOR[state]
            label = STATE_LABEL[state]

            if state != NORMAL:
                cv2.rectangle(frame, (0, 0),
                              (frame.shape[1], frame.shape[0]), color, 14)

            cv2.putText(frame, label,
                        (10, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.3, color, 3)

            debug = f"EAR:{ear:.2f}  기울기:{tilt:+.1f}°"
            cv2.putText(frame, debug,
                        (10, frame.shape[0] - 12),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (180, 180, 180), 1)

            cv2.imshow("18 - 상태 머신 MVP (q: 종료)", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
