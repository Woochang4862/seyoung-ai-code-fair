"""
14회차: MediaPipe 얼굴 랜드마크 입문
────────────────────────────────────
목표
  - 웹캠 영상에서 얼굴 468개 랜드마크를 추출한다
  - 눈 주위 6개 포인트를 직접 골라서 점으로 표시한다

[mediapipe 0.10+] mp.solutions 대신 Tasks API 사용
  - 모델 파일(.task)을 자동 다운로드
  - mp.tasks.vision.FaceLandmarker 사용

랜드마크 번호 참고
  https://ai.google.dev/edge/mediapipe/solutions/vision/face_landmarker
"""

import cv2
import mediapipe as mp
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

# ── Tasks API 초기화 ────────────────────────────────────────────
BaseOptions          = mp.tasks.BaseOptions
FaceLandmarker       = mp.tasks.vision.FaceLandmarker
FaceLandmarkerOptions = mp.tasks.vision.FaceLandmarkerOptions
RunningMode          = mp.tasks.vision.RunningMode

# ── 눈 랜드마크 번호 ─────────────────────────────────────────────
RIGHT_EYE = [33, 160, 158, 133, 153, 144]
LEFT_EYE  = [362, 385, 387, 263, 373, 380]


def get_landmark_pretty_string(landmarks, indices=None, label="Debug"):
    """
    랜드마크 정보를 보기 좋게 출력한다.

    Parameters
    ----------
    landmarks : result.face_landmarks[0] — NormalizedLandmark 리스트
    indices   : 필터링할 랜드마크 번호 목록, None이면 전체 출력
    """
    lines = []

    lines.append(f"[{label}]")
        
    if indices is None:
        indices = range(len(landmarks))

    for idx in indices:
        lm = landmarks[idx]
        line = f"{idx:3d}: x={lm.x:6.3f} y={lm.y:6.3f} z={lm.z:6.3f}"
        lines.append(line)
    return "\n".join(lines)


def draw_text(image, text, position, color=(0, 255, 0), thickness=2):
    """
    지정한 위치에 텍스트를 그린다.
    여러 줄의 텍스트도 지원한다.

    Parameters
    ----------
    image : 텍스트를 그릴 이미지
    text : 텍스트
    position : 텍스트의 위치 (x, y)
    color : 텍스트의 색상 (B, G, R)
    thickness : 텍스트의 두께
    """
    for i, line in enumerate(text.split('\n')):
        y = position[1] + i*20
        cv2.putText(image, line, (position[0], y), cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, thickness)

def main():
    download_model()

    options = FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=RunningMode.VIDEO,   # 웹캠 영상 = VIDEO 모드
        num_faces=1,
    )

    cap = cv2.VideoCapture(0)
    timestamp_ms = 0  # 단조 증가 타임스탬프

    with FaceLandmarker.create_from_options(options) as landmarker:
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            timestamp_ms += 33   # ~30fps 기준 약 33ms씩 증가

            rgb    = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = landmarker.detect_for_video(mp_img, timestamp_ms)

            if result.face_landmarks:
                lm = result.face_landmarks[0]   # 첫 번째 얼굴

                # 오른쪽 눈 → 초록
                draw_text(frame, get_landmark_pretty_string(lm, RIGHT_EYE, "RIGHT_EYE"), (10, 130), (0, 255, 0), 2)
                # 왼쪽 눈 → 파랑
                draw_text(frame, get_landmark_pretty_string(lm, LEFT_EYE, "LEFT_EYE"), (1000, 130), (255, 100, 0), 2)

                # ── TODO 도전 ──────────────────────────────────
                # 아래 번호들을 추가로 찍어보세요
                #   코 끝     : [1]
                #   입술 중앙 : [13, 14]
                #   턱 끝     : [152]
                # draw_points(frame, lm, [1, 13, 14, 152], color=(0, 100, 255))

                cv2.putText(frame, "face detected", (10, 30),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
            else:
                cv2.putText(frame, "face not detected", (10, 30),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2)

            cv2.imshow("14 - MediaPipe Landmark (q: quit)", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
