"""
alert.py — 음성/효과음 알림 헬퍼 모듈
─────────────────────────────────────────
다른 파일에서 import 해서 사용:
    from alert import speak, beep
    speak("졸음 감지! 깨어나세요")
    beep("Sosumi")

특징
  - 비동기 재생 (subprocess.Popen) → 카메라 루프가 멈추지 않는다
  - 같은 알림은 COOLDOWN 초 동안 한 번만 재생 → 매 프레임 스팸 방지
  - macOS 전용 (say / afplay 사용)
    ※ Windows/Linux 환경이면 콘솔 출력으로 대체됨
"""

import subprocess
import platform
import time

_IS_MAC   = platform.system() == "Darwin"
_COOLDOWN = 2.0           # 같은 카테고리 알림 최소 재생 간격 (초)
_last_at  = {}            # 카테고리별 마지막 재생 시각


def _allowed(category: str) -> bool:
    """같은 카테고리 알림이 COOLDOWN 안이면 False (스팸 방지)"""
    now = time.time()
    if now - _last_at.get(category, 0) < _COOLDOWN:
        return False
    _last_at[category] = now
    return True


def speak(text: str, voice: str = "Yuna", category: str = "speak"):
    """
    한국어 음성으로 텍스트 읽기 (비동기).

    Parameters
    ----------
    text     : 읽을 문장
    voice    : macOS 음성 (한국어: Yuna)
    category : 같은 카테고리는 COOLDOWN 동안 한 번만 재생
    """
    if not _allowed(category):
        return
    if _IS_MAC:
        subprocess.Popen(["say", "-v", voice, text])
    else:
        print(f"[음성] {text}")


def beep(sound: str = "Glass", category: str = "beep"):
    """
    macOS 시스템 사운드 재생 (비동기).

    사용 가능한 사운드 (macOS 기본 제공)
      Basso, Blow, Bottle, Frog, Funk, Glass, Hero,
      Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink
    """
    if not _allowed(category):
        return
    if _IS_MAC:
        subprocess.Popen(["afplay", f"/System/Library/Sounds/{sound}.aiff"])
    else:
        print("\a")  # 콘솔 벨


# ── 단독 실행 시 데모 ────────────────────────────────────────────
if __name__ == "__main__":
    print("Glass 사운드 →"); beep("Glass"); time.sleep(_COOLDOWN + 0.5)
    print("Sosumi 사운드 →"); beep("Sosumi"); time.sleep(_COOLDOWN + 0.5)
    print("음성 알림 →"); speak("안녕하세요 정민성님 졸음 감지 시스템입니다"); time.sleep(3)
