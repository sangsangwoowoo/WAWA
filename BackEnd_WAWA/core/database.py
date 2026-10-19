# core/database.py

import os
from dotenv import load_dotenv
from supabase import create_async_client, AsyncClient

load_dotenv()

url: str = os.getenv("SUPABASE_URL")
key: str = os.getenv("SUPABASE_KEY")

async def get_db() -> AsyncClient:
    """
    API 엔드포인트에서 사용할 Supabase 비동기 클라이언트를 생성하고 반환하는 의존성 함수입니다.
    """
    supabase: AsyncClient = await create_async_client(url, key)
    return supabase
