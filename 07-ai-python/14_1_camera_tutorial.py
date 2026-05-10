"""
14-1회차: 웹캠 영상 띄우기
────────────────────────────────────
목표
  - 웹캠 영상을 띄워본다
  - 도형을 그려본다

[OpenCV] 웹캠 영상 띄우기
  - 웹캠 영상 띄우기
  - 도형 그리기

"""

import cv2


def draw_circle(image, center, radius, color=(0, 255, 0), thickness=2):
    """
    지정한 중심점과 반지름으로 원을 그린다.

    Parameters
    ----------
    image : 원을 그릴 이미지
    center : 원의 중심점 (x, y)
    radius : 원의 반지름
    color : 원의 색상 (B, G, R)
    """
    cv2.circle(image, center, radius, color, thickness)

def draw_rectangle(image, pt1, pt2, color=(0, 255, 0), thickness=2):
    """
    지정한 두 점으로 사각형을 그린다.

    Parameters
    ----------
    image : 사각형을 그릴 이미지
    pt1 : 사각형의 왼쪽 위 점 (x, y)
    pt2 : 사각형의 오른쪽 아래 점 (x, y)
    color : 사각형의 색상 (B, G, R)
    thickness : 선의 두께
    """
    cv2.rectangle(image, pt1, pt2, color, thickness)


def main():
    cap = cv2.VideoCapture(0)
    timestamp_ms = 0  # 단조 증가 타임스탬프

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        # 도형 그리기
        draw_circle(frame, (1000, 500),200, (0, 0, 255))
        draw_rectangle(frame, (200, 200), (300, 300), (255,0,0))
        cv2.putText(frame, "Hello", (1000, 300),
            cv2.FONT_HERSHEY_SIMPLEX, 8, (0, 255, 0), 2)

        cv2.imshow("14-1 웹캠 영상 띄우기 (q: 종료)", frame)
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
