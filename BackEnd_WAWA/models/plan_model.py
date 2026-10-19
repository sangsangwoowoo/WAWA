# models/plan_model.py

from pydantic import BaseModel, Field
from typing import List, Dict

# [복구] 기존 직접 생성 요청 모델 (DB 저장을 위해 내부적으로 사용)
class LearningPlanRequest(BaseModel):
    user_id: str
    current_level: int
    goal_level: int
    frequency_type: str
    frequency_value: int
    session_duration_minutes: int
    preferred_styles: List[str]

# ▼▼▼ [수정] API가 직접 받을 요청 모델 변경 ▼▼▼
# 분, 횟수를 각각 받도록 필드를 수정합니다.
class DirectPlanRequest(BaseModel):
    conversation_duration: int = Field(default=30, ge=0, le=120, description="회화 학습 시간(분)")
    grammar_count: int = Field(default=3, ge=0, le=50, description="문법 연습 횟수")
    pronunciation_count: int = Field(default=3, ge=0, le=50, description="발음 연습 횟수")

# [복구] 템플릿 선택 요청 모델
class SelectPlanTemplateRequest(BaseModel):
    user_id: str
    template_id: str

# [복구] DB 저장용 모델
class LearningPlanInternal(BaseModel):
    user_id: str
    user_level: int
    goal_level: int
    estimated_days: int
    frequency_description: str
    total_session_duration: int
    time_distribution: Dict[str, int]
    plan_summary: str

# [복구] API 응답 모델
class LearningPlanResponse(BaseModel):
    id: int
    created_at: str
    user_id: str
    user_level: int
    goal_level: int
    estimated_days: int
    frequency_description: str
    total_session_duration: int
    time_distribution: Dict[str, int]
    plan_summary: str
    class Config:
        orm_mode = True

# [복구] 템플릿 목록 응답 모델
class PlanTemplateResponse(BaseModel):
    id: str
    name: str
    description: str