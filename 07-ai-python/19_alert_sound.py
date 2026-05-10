"""
19회차: 음성/효과음 경고 추가
──────────────────────────────────
18회차 상태 머신에 소리를 입혔다.

울리는 알림
  DROWSY    → "졸음입니다 일어나세요" (음성)
  COLLAPSED → 효과음 + "위험 상황입니다" (음성)

핵심 패턴
  - 매 프레임마다 호출해도 alert 모듈이 COOLDOWN으로 스팸 차단
  - 상태가 바뀌는 순간이 아닌 '상태가 위험한 동안' 계속 호출 → 코드 단순
"""

import cv2
import mediapipe as mp
import time
import math
import urllib.request
import os

from alert import speak, beep   # ← 새로 추가된 모듈

# ── 모델 다운로드 ───────────────────────────────────────────────
MODEL_PATH = "face_landmarker.task"
MODEL_URL  = (
    "https://storage.googleapis.com/mediapipe-models/"
    "face_landmarker/face_landmarker/float16/1/face_landmarker.task"
)

def download_model():
    if not os.path.exists(MODEL_PATH):
        print("모델 파일 다운로드 중... (처음 한 번만)")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
        print("완료!")

# ── Tasks API ───────────────────────────────────────────────────
BaseOptions          = mp.tasks.BaseOptions
FaceLandmarker       = mp.tasks.vision.FaceLandmarker
FaceLandmarkerOptions = mp.tasks.vision.FaceLandmarkerOptions
RunningMode          = mp.tasks.vision.RunningMode

RIGHT_EYE = [33, 160, 158, 133, 153, 144]
LEFT_EYE  = [362, 385, 387, 263, 373, 380]

EAR_THRESHOLD   = 0.25
DROWSY_SECONDS  = 3.0
TILT_THRESHOLD  = 30.0
MISSING_SECONDS = 2.0
DROP_RATIO      = 0.25
DROP_TIME       = 0.5

NORMAL, DROWSY, COLLAPSED = "NORMAL", "DROWSY", "COLLAPSED"

STATE_LABEL = {NORMAL: "✓ 정상", DROWSY: "⚠ 졸음", COLLAPSED: "🚨 위험"}
STATE_COLOR = {
    NORMAL:    (0, 200, 0),
    DROWSY:    (0, 165, 255),
    COLLAPSED: (0, 0, 255),
}

# ── 헬퍼 함수 (16/18회차에서 그대로 가져옴) ─────────────────────

def distance(p1, p2):
    return ((p1.x - p2.x) ** 2 + (p1.y - p2.y) ** 2) ** 0.5

def calculate_ear(eye):
    return (distance(eye[1], eye[5]) + distance(eye[2], eye[4])) / (2.0 * distance(eye[0], eye[3]))

def get_eye(lm, indices):
    return [lm[i] for i in indices]

def face_tilt_angle(lm):
    r, l = lm[33], lm[263]
    return math.degrees(math.atan2(l.y - r.y, l.x - r.x))

def is_sudden_drop(face_y, prev_y):
    return prev_y is not None and face_y - prev_y > DROP_RATIO


def check_state(face_detected, ear, eye_closed_time,
                tilt, face_y, prev_y, face_missing_start):
    now = time.time()
    if not face_detected:
        if face_missing_start is None:
            face_missing_start = now
        elif now - face_missing_start >= MISSING_SECONDS:
            return COLLAPSED, face_missing_start
        return NORMAL, face_missing_start

    face_missing_start = None
    if is_sudden_drop(face_y, prev_y):
        return COLLAPSED, face_missing_start
    if abs(tilt) > TILT_THRESHOLD:
        return COLLAPSED, face_missing_start
    if ear < EAR_THRESHOLD and eye_closed_time >= DROWSY_SECONDS:
        return DROWSY, face_missing_start
    return NORMAL, face_missing_start


# ── 상태 → 알림 매핑 (이 함수가 19회차의 핵심!) ─────────────────

def play_alert(state):
    """
    현재 상태에 맞는 소리/음성을 재생.
    매 프레임마다 호출되지만 alert 모듈이 COOLDOWN으로 스팸 차단.
    """
    if state == DROWSY:
        speak("졸음입니다. 일어나세요!", category="drowsy")
    elif state == COLLAPSED:
        beep("Sosumi", category="collapsed_beep")
        speak("위험 상황입니다. 즉시 확인하세요!", category="collapsed_voice")


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
    timestamp_ms       = 0
    global last_check_time
    last_check_time = time.time()

    # 시작 시 안내 음성
    speak("졸음 감지 시스템을 시작합니다", category="startup")

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
                r = get_eye(lm, RIGHT_EYE)
                l = get_eye(lm, LEFT_EYE)
                ear = (calculate_ear(r) + calculate_ear(l)) / 2.0

                if ear < EAR_THRESHOLD:
                    if eye_closed_start is None:
                        eye_closed_start = time.time()
                    eye_closed_time = time.time() - eye_closed_start
                else:
                    eye_closed_start = None
                    eye_closed_time = 0.0

                tilt   = face_tilt_angle(lm)
                face_y = lm[1].y

            state, face_missing_start = check_state(
                face_detected, ear, eye_closed_time,
                tilt, face_y, prev_face_y, face_missing_start,
            )

            if time.time() - last_check_time > DROP_TIME:
                last_check_time = time.time()
                prev_face_y = face_y

            # ★ 사운드 알림 (19회차의 새 부분) ★
            play_alert(state)

            # 화면 렌더링
            color = STATE_COLOR[state]
            label = STATE_LABEL[state]
            if state != NORMAL:
                cv2.rectangle(frame, (0, 0),
                              (frame.shape[1], frame.shape[0]), color, 14)
            cv2.putText(frame, label, (10, 45),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.3, color, 3)
            cv2.putText(frame, f"EAR:{ear:.2f}  기울기:{tilt:+.1f}°",
                        (10, frame.shape[0] - 12),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (180, 180, 180), 1)

            cv2.imshow("19 - 음성 경고 시스템 (q: 종료)", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
