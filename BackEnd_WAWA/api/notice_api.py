# '공지사항' 관련 API 엔드포인트를 정의하는 파일입니다.
from fastapi import APIRouter, Depends, HTTPException, status
from supabase import AsyncClient # 👈 Session 대신 AsyncClient를 import
from typing import List

from core.database import get_db
from core.dependencies import get_current_admin
from models import notice_model
from services import notice_service

router = APIRouter()

@router.get("/ping", tags=["Notices"])
def ping_notice_router():
    """
    이 notice_api.py 파일이 main.py에 정상적으로 연결되었는지 확인하기 위한
    간단한 테스트용 엔드포인트입니다.
    """
    return {"message": "Success! The notice_api router is working correctly."}

@router.post("/", response_model=notice_model.NoticeResponse, status_code=status.HTTP_201_CREATED)
async def create_notice(
        notice: notice_model.NoticeCreate,
        db: AsyncClient = Depends(get_db),
        current_admin: dict = Depends(get_current_admin)
):
    return await notice_service.create_new_notice(db=db, notice_create=notice)

@router.get("/", response_model=List[notice_model.NoticeResponse])
async def read_notices(
        skip: int = 0, limit: int = 10, db: AsyncClient = Depends(get_db)
):
    return await notice_service.get_all_notices(db=db, skip=skip, limit=limit)

@router.get("/{notice_id}", response_model=notice_model.NoticeResponse)
async def read_notice(notice_id: int, db: AsyncClient = Depends(get_db)):
    db_notice = await notice_service.get_notice_by_id(db=db, notice_id=notice_id)
    if db_notice is None:
        raise HTTPException(status_code=404, detail="Notice not found")
    return db_notice

@router.put("/{notice_id}", response_model=notice_model.NoticeResponse)
async def update_notice(
        notice_id: int,
        notice_update: notice_model.NoticeUpdate,
        db: AsyncClient = Depends(get_db),
        current_admin: dict = Depends(get_current_admin)
):
    updated_notice = await notice_service.update_existing_notice(db=db, notice_id=notice_id, notice_update=notice_update)
    if updated_notice is None:
        raise HTTPException(status_code=404, detail="Notice not found")
    return updated_notice

@router.delete("/{notice_id}", status_code=status.HTTP_200_OK)
async def delete_notice(
        notice_id: int,
        db: AsyncClient = Depends(get_db),
        current_admin: dict = Depends(get_current_admin)
):
    if not await notice_service.delete_notice_by_id(db=db, notice_id=notice_id):
        raise HTTPException(status_code=404, detail="Notice not found")