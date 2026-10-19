# run_and_test.py (최종 수정본)

import requests
import socket
import threading
import time
import os
import sys
import subprocess # 👈 subprocess 라이브러리 추가

# --- 설정 ---
PORT = 8001
APP_MODULE = "main:app"
HOST_IP = "172.30.1.55" # 👈 본인의 IP 주소로 고정

def run_server():
    """Uvicorn 서버를 명확한 경로에서 직접 실행합니다."""

    # 현재 가상환경의 파이썬 실행 파일 경로를 가져옵니다.
    python_executable = sys.executable
    # 이 스크립트가 있는 폴더의 경로를 가져옵니다.
    script_directory = os.path.dirname(os.path.abspath(__file__))

    # 실행할 uvicorn 명령어 리스트를 만듭니다.
    command = [
        python_executable,
        "-m", "uvicorn",
        APP_MODULE,
        "--host", HOST_IP,
        "--port", str(PORT)
    ]

    print(f"✅ 다음 명령어를 실행합니다: {' '.join(command)}")
    print(f"✅ 실행 위치: {script_directory}")

    # [핵심] 현재 파일이 있는 디렉토리(BackEnd_WAWA)에서 명령어를 실행하도록 강제합니다.
    subprocess.run(command, cwd=script_directory)

# --- 메인 테스트 로직 (수정 없음) ---
if __name__ == "__main__":
    server_thread = threading.Thread(target=run_server, daemon=True)
    server_thread.start()
    print("🚀 테스트 서버를 백그라운드에서 시작합니다... (5초 대기)")
    time.sleep(5)

    test_url = f"http://{HOST_IP}:{PORT}/api/notices/ping"

    print("-" * 50)
    print(f"📡 {test_url} 주소로 네트워크 테스트를 시도합니다...")

    try:
        response = requests.get(test_url, timeout=10)

        if response.status_code == 200:
            print("\n✅ [최종 진단 결과]: 테스트 성공!")
            print("   - 서버가 올바르게 실행되었고, 외부 IP 접속에 정상 응답했습니다.")
            print("   - 이제 Flutter 앱에서 다시 시도해보세요!")
        else:
            print(f"\n❌ [최종 진단 결과]: 테스트 실패! (상태 코드: {response.status_code})")
            print(f"   - 원인: 서버 코드 내에 여전히 문제가 있을 수 있습니다.")
            print(f"   - 응답 내용: {response.text}")

    except requests.ConnectionError as e:
        print("\n❌ [최종 진단 결과]: 테스트 실패! (연결 거부)")
        print(f"   - 원인: 서버 프로세스가 시작되지 못했습니다. 터미널의 서버 로그를 확인하세요.")
        print(f"   - 상세 오류: {e}")
    finally:
        print("-" * 50)
        print("ℹ️ 테스트를 종료합니다. (Ctrl+C를 눌러 서버를 완전히 종료하세요)")