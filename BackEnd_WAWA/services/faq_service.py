# 'FAQ' 관련 비즈니스 로직을 처리하는 파일입니다.
from supabase import AsyncClient
from models import faq_model
from db import faq_supabase

# --- 새 FAQ 생성 서비스 ---
async def create_new_faq(db: AsyncClient, faq_create: faq_model.FAQCreate):
    return await faq_supabase.create_faq(db=db, faq=faq_create)

# --- 모든 FAQ 조회 서비스 ---
async def get_all_faqs(db: AsyncClient, skip: int = 0, limit: int = 100):
    return await faq_supabase.get_faqs(db=db, skip=skip, limit=limit)

# --- 특정 FAQ 조회 서비스 ---
async def get_faq_by_id(db: AsyncClient, faq_id: int):
    return await faq_supabase.get_faq(db=db, faq_id=faq_id)

# --- FAQ 수정 서비스 ---
async def update_existing_faq(db: AsyncClient, faq_id: int, faq_update: faq_model.FAQUpdate):
    update_data = faq_update.dict(exclude_unset=True)
    return await faq_supabase.update_faq(db=db, faq_id=faq_id, update_data=update_data)

# --- FAQ 삭제 서비스 ---
async def delete_faq_by_id(db: AsyncClient, faq_id: int):
    return await faq_supabase.delete_faq(db=db, faq_id=faq_id)
