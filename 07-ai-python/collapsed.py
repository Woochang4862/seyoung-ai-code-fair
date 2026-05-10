
def face_tilt_angle(lm): # 기울기
    x1=lm[33].x
    x2=lm[263].x
    y1=lm[33].y
    y2=lm[263].y
    dx=x1-x2
    dy=y1-y2
    return dy/dx

DROP_RATIO = 0.25

def is_sudden_drop(face_y, prev_y): # 급격히 떨어짐
    return face_y-prev_y>DROP_RATIO
    


class NormalizedLandmark:
    def __init__(self, x, y, z):
        self.x = x
        self.y = y
        self.z = z

p33 = NormalizedLandmark(0.5, 0.5, 0.5)
p263 = NormalizedLandmark(1.0, 1.0, 1.0)

lm = {33:p33, 263:p263}

print(face_tilt_angle(lm))

face_y = 0.
prev_y = 0.75
print(is_sudden_drop(face_y, prev_y))