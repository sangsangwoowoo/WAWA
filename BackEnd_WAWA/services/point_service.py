# services/point_service.py

from fastapi import HTTPException
from models.point_model import PointTransactionRequest
from db import point_supabase
from supabase import AsyncClient
import traceback # 디버깅을 위해 traceback 모듈 추가
from uuid import UUID

async def process_point_transaction(request: PointTransactionRequest, db: AsyncClient) -> dict:
    # 이 함수가 호출되었는지 확인하기 위한 로그
    print(f"--- 포인트 서비스 함수 시작: User {request.user_id}, Amount {request.amount} ---")

    try:
        # DB 함수를 호출하여 실제 로직 실행
        final_points = await point_supabase.update_points_and_log(
            db=db,
            user_id=request.user_id,
            amount=request.amount,
            reason=request.reason
        )

        print(f"--- 포인트 서비스 함수 성공: 최종 포인트 {final_points} ---")

        return {
            "status": "success",
            "user_id": str(request.user_id),
            "message": f"거래 성공! 최종 포인트: {final_points}",
            "final_points": final_points
        }
    except Exception as e:
        # 'try' 블록에서 어떤 에러가 발생하든 이 부분이 실행됩니다.
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        print("!!!!!!!!!!!!!!!!! 에러가 감지되었습니다 !!!!!!!!!!!!!!!!!!")
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        traceback.print_exc() # 이것이 터미널에 상세한 에러 내용을 출력합니다.
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")

        # 클라이언트에게는 일반적인 500 에러를 보냅니다.
        raise HTTPException(status_code=500, detail="Internal Server Error")

async def get_user_point_history(user_id: UUID, db: AsyncClient) -> list:
    """사용자의 포인트 거래 내역을 조회하는 서비스 로직"""
    try:
        history = await point_supabase.get_point_transactions_by_user(db=db, user_id=user_id)
        return history
    except Exception as e:
        print(f"포인트 내역 서비스 오류: {e}")
        raise HTTPException(status_code=500, detail="포인트 내역을 불러오는 중 오류가 발생했습니다.")