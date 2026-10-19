# 'FAQ' 관련 데이터 형식을 Pydantic 모델로 정의합니다.
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

# --- FAQ의 기본 필드를 정의하는 기본 모델 ---
class FAQBase(BaseModel):
    question: str
    answer: str

# --- FAQ 생성을 위한 요청 스키마 ---
class FAQCreate(FAQBase):
    pass

# --- FAQ 수정을 위한 요청 스키마 ---
class FAQUpdate(BaseModel):
    question: Optional[str] = None
    answer: Optional[str] = None

# --- FAQ API 응답 스키마 ---
class FAQResponse(FAQBase):
    id: int
    created_at: datetime

    class Config:
        orm_mode = True