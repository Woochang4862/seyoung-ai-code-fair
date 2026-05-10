"""
16회차: EAR(Eye Aspect Ratio) 알고리즘 — 눈 감김 감지
──────────────────────────────────────────────────────
EAR 공식
         세로 거리1 + 세로 거리2
  EAR = ────────────────────────
              2 × 가로 거리

  눈이 열릴수록 값이 크고, 감길수록 0에 가까워진다.
  보통 EAR < 0.25 이면 눈이 감긴 것으로 판단한다.
"""

import cv2
import mediapipe as mp
import time
import urllib.request
import os

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

BaseOptions          = mp.tasks.BaseOptions
FaceLandmarker       = mp.tasks.vision.FaceLandmarker
FaceLandmarkerOptions = mp.tasks.vision.FaceLandmarkerOptions
RunningMode          = mp.tasks.vision.RunningMode

RIGHT_EYE = [33, 160, 158, 133, 153, 144]
LEFT_EYE  = [362, 385, 387, 263, 373, 380]

EAR_THRESHOLD  = 0.25   # 이 값 미만 → 눈 감김
DROWSY_SECONDS = 0.0    # 이 시간(초) 이상 감기면 경고


# ── 핵심 함수 (학생이 직접 작성) ────────────────────────────────

def distance(p1, p2):
    """
    두 랜드마크 사이의 유클리드 거리.
    p1, p2 는 NormalizedLandmark (x, y 값 0~1 비율)

    TODO: 수식을 채워보세요
      √( (x2-x1)² + (y2-y1)² )
    """
    return ((p1.x - p2.x) ** 2 + (p1.y - p2.y) ** 2) ** 0.5


def calculate_ear(eye):
    """
    눈 6개 랜드마크로 EAR 값 계산.
    eye = [끝(0), 위1(1), 위2(2), 끝(3), 아래1(4), 아래2(5)]

    TODO: 아래 세 줄의 빈칸을 채워보세요
    """
    세로1 = distance(eye[1], eye[5])
    세로2 = distance(eye[2], eye[4])
    가로  = distance(eye[0], eye[3])
    return (세로1 + 세로2) / (2.0 * 가로)


def get_eye(landmarks, indices):
    return [landmarks[i] for i in indices]


# ── 메인 루프 ────────────────────────────────────────────────────

def main():
    download_model()

    options = FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=RunningMode.VIDEO,
        num_faces=1,
    )

    cap = cv2.VideoCapture(0)
    eye_closed_start = None
    timestamp_ms     = 0

    with FaceLandmarker.create_from_options(options) as landmarker:
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            timestamp_ms += 33

            rgb    = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = landmarker.detect_for_video(mp_img, timestamp_ms)

            ear_value    = 0.0
            status       = "Face Not Detected"
            status_color = (180, 180, 180)

            if result.face_landmarks:
                lm = result.face_landmarks[0]

                r = get_eye(lm, RIGHT_EYE)
                l = get_eye(lm, LEFT_EYE)
                ear_value = (calculate_ear(r) + calculate_ear(l)) / 2.0

                if ear_value < EAR_THRESHOLD:
                    if eye_closed_start is None:
                        eye_closed_start = time.time()
                    elapsed = time.time() - eye_closed_start

                    if elapsed >= DROWSY_SECONDS:
                        status       = f"⚠ Drowsy Detected! ({elapsed:.1f}s)"
                        status_color = (0, 0, 255)
                        cv2.rectangle(frame, (0, 0),
                                      (frame.shape[1], frame.shape[0]),
                                      (0, 0, 255), 12)
                    else:
                        status       = f"Eyes Closed ({elapsed:.1f}s)"
                        status_color = (0, 165, 255)
                else:
                    eye_closed_start = None
                    status           = "Normal"
                    status_color     = (0, 200, 0)

            cv2.putText(frame, f"EAR : {ear_value:.3f}",
                        (10, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (200, 200, 200), 2)
            cv2.putText(frame, f"Status: {status}",
                        (10, 70), cv2.FONT_HERSHEY_SIMPLEX, 0.9, status_color, 2)
            cv2.putText(frame, f"Threshold: {EAR_THRESHOLD}",
                        (10, frame.shape[0] - 15),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (150, 150, 150), 1)

            cv2.imshow("16 - EAR Drowsy Detection (q: 종료)", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
