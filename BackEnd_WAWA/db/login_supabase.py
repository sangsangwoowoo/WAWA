# db/login_supabase.py

from supabase import create_client, Client as AsyncClient
import os
from dotenv import load_dotenv

load_dotenv()

# 전역 변수로 한 번만 설정
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

print(f"=== login_supabase.py 로드 시 확인 ===")
print(f"URL: {SUPABASE_URL}")
print(f"KEY 길이: {len(SUPABASE_KEY) if SUPABASE_KEY else 0}")
print(f"=====================================")

async def get_supabase_client() -> AsyncClient:
    """비동기 Supabase 클라이언트 반환"""
    if not SUPABASE_URL or not SUPABASE_KEY:
        raise ValueError("Supabase 환경 변수가 설정되지 않았습니다")

    print(f"AsyncClient 생성 - KEY 길이: {len(SUPABASE_KEY)}")

    # acreate_client 사용
    from supabase import acreate_client
    client = await acreate_client(SUPABASE_URL, SUPABASE_KEY)
    return client
