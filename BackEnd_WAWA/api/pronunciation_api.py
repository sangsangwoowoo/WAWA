from fastapi import APIRouter, HTTPException, Depends, Query
from core.dependencies import get_current_user
from core.database import get_db
from supabase import AsyncClient
from models.pronunciation_model import (
    PronunciationHistoryResponse,
    PronunciationHistoryDetail,
    PronunciationStatistics
)
from db import pronunciation_supabase
from typing import List

router = APIRouter()

@router.get("/history", response_model=List[PronunciationHistoryResponse])
async def get_pronunciation_history(
        limit: int = Query(20, ge=1, le=100),
        offset: int = Query(0, ge=0),
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """발음 분석 이력 목록 조회"""
    try:
        user_id = current_user.get('user_id')
        history = await pronunciation_supabase.get_pronunciation_history(
            db, user_id, limit, offset
        )
        return [PronunciationHistoryResponse(**item) for item in history]
    except Exception as e:
        print(f"발음 이력 조회 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/history/{result_id}", response_model=PronunciationHistoryDetail)
async def get_pronunciation_detail(
        result_id: str,  # ✅ int → str
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """특정 발음 분석 결과 상세 조회"""
    try:
        user_id = current_user.get('user_id')
        detail = await pronunciation_supabase.get_pronunciation_detail(
            db, result_id, user_id
        )

        if not detail:
            raise HTTPException(status_code=404, detail="분석 결과를 찾을 수 없습니다.")

        return PronunciationHistoryDetail(**detail)
    except HTTPException:
        raise
    except Exception as e:
        print(f"발음 상세 조회 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/history/{result_id}")
async def delete_pronunciation_history(
        result_id: str,  # ✅ int → str
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """발음 분석 이력 삭제"""
    try:
        user_id = current_user.get('user_id')
        await pronunciation_supabase.delete_pronunciation_history(
            db, result_id, user_id
        )
        return {"message": "삭제되었습니다."}
    except Exception as e:
        print(f"발음 이력 삭제 오류: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/statistics", response_model=PronunciationStatistics)
async def get_pronunciation_statistics(
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """발음 분석 통계"""
    try:
        user_id = current_user.get('user_id')
        stats = await pronunciation_supabase.get_pronunciation_statistics(db, user_id)
        return PronunciationStatistics(**stats)
    except Exception as e:
        print(f"발음 통계 조회 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))
