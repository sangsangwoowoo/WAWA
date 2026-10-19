# api/points_api.py
from fastapi import APIRouter, Depends
from models.point_model import PointTransactionRequest, PointTransactionResponse # PointTransactionResponse import 추가
from services import point_service
from core.database import get_db
from supabase import AsyncClient
from typing import List # List import 추가
from core.dependencies import get_current_user # 사용자 인증을 위한 의존성 추가
from models.user_model import UserResponse # UserResponse import 추가 (경로 확인 필요)

router = APIRouter()

# 엔드포인트를 비동기(async)로 변경하고, Depends(get_db)를 사용
@router.post("/transaction", response_model=dict)
async def execute_point_transaction(request: PointTransactionRequest, db: AsyncClient = Depends(get_db)):
    """포인트 적립 또는 사용 API 엔드포인트"""
    # 서비스 함수 호출 시 db 클라이언트를 전달
    return await point_service.process_point_transaction(request, db)

@router.get("/history", response_model=List[PointTransactionResponse])
async def get_point_history(
        current_user: UserResponse = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """현재 로그인된 사용자의 포인트 거래 내역을 조회합니다."""
    # current_user는 딕셔너리 형태로 반환되므로 키로 접근합니다.
    user_id = current_user['user_id']
    return await point_service.get_user_point_history(user_id=user_id, db=db)