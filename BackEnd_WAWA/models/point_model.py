# models/point_model.py
# 포인트 거래 요청 시 필요한 데이터 구조 정의

from pydantic import BaseModel
from uuid import UUID
from datetime import datetime

class PointTransactionRequest(BaseModel):
    user_id: UUID
    amount: int
    reason: str

class PointTransactionResponse(BaseModel):
    id: int
    created_at: datetime
    change_amount: int
    reason: str

    class Config:
        from_attributes = True # DB 모델 객체를 Pydantic 모델로 자동 변환