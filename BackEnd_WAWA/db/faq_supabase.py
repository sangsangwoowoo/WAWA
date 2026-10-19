# 'FAQ' 모델에 대한 데이터베이스 CRUD 작업을 정의하는 파일입니다.
from supabase import AsyncClient
from models import faq_model

# --- 특정 FAQ 조회 ---
async def get_faq(db: AsyncClient, faq_id: int):
    response = await db.table("faqs").select("*").eq("id", faq_id).limit(1).single().execute()
    return response.data

# --- 모든 FAQ 조회 (페이지네이션) ---
async def get_faqs(db: AsyncClient, skip: int = 0, limit: int = 100):
    response = await db.table("faqs").select("*").order("id", desc=True).range(skip, skip + limit - 1).execute()
    return response.data

# --- FAQ 생성 ---
async def create_faq(db: AsyncClient, faq: faq_model.FAQCreate):
    faq_data = faq.dict()
    response = await db.table("faqs").insert(faq_data).execute()
    return response.data[0] if response.data else None

# --- FAQ 수정 ---
async def update_faq(db: AsyncClient, faq_id: int, update_data: dict):
    response = await db.table("faqs").update(update_data).eq("id", faq_id).execute()
    return response.data[0] if response.data else None

# --- FAQ 삭제 ---
async def delete_faq(db: AsyncClient, faq_id: int):
    response = await db.table("faqs").delete().eq("id", faq_id).execute()
    return response.data is not None
