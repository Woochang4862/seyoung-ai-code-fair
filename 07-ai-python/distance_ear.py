def distance(p1, p2):
    """
    두 NormalizedLandmark 사이의 거리.
    p1, p2 의 .x, .y 는 0~1 비율값.
    """
    return ((p1.x-p2.x)**2+(p1.y-p2.y)**2)**0.5


def calculate_ear(eye):
    """
    eye = [P1, P2, P3, P4, P5, P6] 순서 리스트 (NormalizedLandmark 6개)
    """
    ear = (distance(eye[1],eye[5])+distance(eye[2],eye[4]))/(2*distance(eye[0],eye[3]))
    return ear

class NormalizedLandmark:
    def __init__(self, x, y, z):
        self.x = x
        self.y = y
        self.z = z
        

p1 = NormalizedLandmark(0.5, 0.5, 0.5)
p2 = NormalizedLandmark(1.0, 1.0, 1.0)
print(distance(p1, p2))

p3 = NormalizedLandmark(0.5, 1.5, 0.5)
p4 = NormalizedLandmark(1.0, 2.0, 1.0)
p5 = NormalizedLandmark(0.5, 3.5, 0.5)
p6 = NormalizedLandmark(1.0, 4.0, 1.0)
print(calculate_ear([p1, p2, p3, p4, p5, p6]))