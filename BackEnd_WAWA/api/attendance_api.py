# '출석 체크' 관련 API 엔드포인트를 정의하는 파일입니다.
from fastapi import APIRouter, Depends, HTTPException, status
from supabase import AsyncClient # 👈 Session 대신 AsyncClient를 import
from typing import List

from core.database import get_db
from core.dependencies import get_current_user
from services import attendance_service
from models import attendance_model

router = APIRouter()

# --- 출석 체크 API ---
@router.post("/check-in", response_model=attendance_model.AttendanceResponse)
async def check_in_attendance(
        db: AsyncClient = Depends(get_db), current_user: dict = Depends(get_current_user)
):
    attendance_record = await attendance_service.mark_attendance(db=db, user_id=current_user['user_id'])
    if attendance_record is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Already checked in today",
        )
    return attendance_record

# --- 출석 기록 조회 API ---
@router.get("/history", response_model=List[attendance_model.AttendanceResponse])
async def get_attendance_history(
        db: AsyncClient = Depends(get_db), current_user: dict = Depends(get_current_user)
):
    return await attendance_service.get_user_attendance_history(db=db, user_id=current_user['user_id'])

# --- 출석 통계 조회 API ---
@router.get("/stats", response_model=attendance_model.AttendanceStatsResponse)
async def get_attendance_stats(
        db: AsyncClient = Depends(get_db), current_user: dict = Depends(get_current_user)
):
    return await attendance_service.calculate_stats(db=db, user_id=current_user['user_id'])
