# 'Notice' 모델에 대한 데이터베이스 CRUD 작업을 정의하는 파일입니다.
from supabase import AsyncClient
from models import notice_model

# --- 특정 공지사항 조회 ---
async def get_notice(db: AsyncClient, notice_id: int):
    response = await db.table("notices").select("*").eq("id", notice_id).limit(1).single().execute()
    return response.data

# --- 모든 공지사항 조회 (페이지네이션) ---
async def get_notices(db: AsyncClient, skip: int = 0, limit: int = 100):
    response = await db.table("notices").select("*").order("id", desc=True).range(skip, skip + limit - 1).execute()
    return response.data

# --- 공지사항 생성 ---
async def create_notice(db: AsyncClient, notice: notice_model.NoticeCreate):
    notice_data = notice.dict()
    response = await db.table("notices").insert(notice_data).execute()
    return response.data[0] if response.data else None

# --- 공지사항 수정 ---
async def update_notice(db: AsyncClient, notice_id: int, update_data: dict):
    response = await db.table("notices").update(update_data).eq("id", notice_id).execute()
    return response.data[0] if response.data else None

# --- 공지사항 삭제 ---
async def delete_notice(db: AsyncClient, notice_id: int):
    response = await db.table("notices").delete().eq("id", notice_id).execute()
    return response.data is not None
