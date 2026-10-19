# check_admin_status.py

import os
import asyncio
from dotenv import load_dotenv
from supabase import create_client

# --- 설정 ---
# 테스트하려는 사용자의 이메일(username)을 정확히 입력하세요.
TEST_USERNAME = "030419s@naver.com" # 👈 본인의 관리자 계정 이메일로 변경

async def main():
    """user_account 테이블에서 특정 사용자의 is_admin 값을 직접 조회합니다."""

    print("-" * 50)
    print(f"'{TEST_USERNAME}' 사용자의 관리자 상태를 확인합니다...")

    load_dotenv()
    url: str = os.getenv("SUPABASE_URL")
    key: str = os.getenv("SUPABASE_KEY")

    if not url or not key:
        print("❌ Supabase URL 또는 KEY를 .env 파일에서 찾을 수 없습니다.")
        return

    try:
        # Supabase 비동기 클라이언트 생성
        supabase = create_client(url, key)

        # 'user_account' 테이블에서 'email' 필드가 일치하는 사용자를 찾습니다.
        response = supabase.table("user_account").select("is_admin").eq("email", TEST_USERNAME).limit(1).single().execute()

        print("\n--- Supabase 응답 결과 ---")
        print(response)
        print("-" * 50)

        if response.data:
            is_admin_value = response.data.get('is_admin')
            print(f"\n✅ [최종 진단 결과]: 조회 성공!")
            print(f"   - DB에 저장된 is_admin 값: {is_admin_value}")
            print(f"   - 데이터 타입: {type(is_admin_value)}")
            if is_admin_value is True:
                print("   - 진단: 데이터베이스는 정상입니다. 문제가 FastAPI 코드 어딘가에 있습니다.")
            else:
                print("   - 진단: 데이터베이스의 is_admin 값이 false이거나 다른 값입니다. Supabase 대시보드에서 다시 확인해주세요.")
        else:
            print("\n❌ [최종 진단 결과]: 사용자 조회 실패!")
            print(f"   - 진단: '{TEST_USERNAME}' 사용자를 'user_account' 테이블에서 찾을 수 없습니다.")
            print("   - 확인 사항: 1) 사용자 이메일이 정확한지, 2) 'user_account' 테이블 이름이 맞는지 확인해주세요.")

    except Exception as e:
        print(f"\n❌ [최종 진단 결과]: 테스트 중 오류 발생!")
        print(f"   - 상세 오류: {e}")

if __name__ == "__main__":
    asyncio.run(main())