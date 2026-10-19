from pydantic import BaseModel, Field, field_validator
from typing import Optional, Dict, List, Union
from datetime import datetime

# 학습 목표
class LearningGoal(BaseModel):
    conversation_goal: int = Field(0, description="회화 학습 목표 시간(분)")
    grammar_goal: int = Field(0, description="문법 연습 목표 횟수")
    pronunciation_goal: int = Field(0, description="발음 연습 목표 횟수")
    created_at: Union[str, datetime] = Field(default_factory=lambda: datetime.now())

    @field_validator('created_at', mode='before')
    @classmethod
    def validate_created_at(cls, v):
        if v is None:
            return datetime.now()
        if isinstance(v, str):
            try:
                return datetime.fromisoformat(v.replace('Z', '+00:00'))
            except:
                return datetime.now()
        return v

# 학습 로그
class LearningLog(BaseModel):
    log_type: str = Field(..., description="로그 타입: conversation, grammar, pronunciation")
    duration: Optional[int] = Field(None, description="회화 시간(분)")
    count: Optional[int] = Field(None, description="연습 횟수")
    created_at: Optional[Union[str, datetime]] = Field(
        default_factory=lambda: datetime.now().isoformat(),
        description="생성 시간"
    )

    @field_validator('log_type')
    @classmethod
    def validate_log_type(cls, v):
        allowed_types = ['conversation', 'grammar', 'pronunciation']
        if v not in allowed_types:
            raise ValueError(f'log_type은 {allowed_types} 중 하나여야 합니다.')
        return v

    @field_validator('created_at', mode='before')
    @classmethod
    def validate_created_at(cls, v):
        if v is None:
            return datetime.now().isoformat()
        if isinstance(v, datetime):
            return v.isoformat()
        return v
# 사용자 정보
class User(BaseModel):
    user_id: str
    learning_logs: Optional[List[LearningLog]] = Field(default_factory=list)  # 수정
    learning_goals: Optional[Dict] = None

# 전체 누적 통계
class OverallStats(BaseModel):
    total_conversation_duration: int = 0
    total_grammar_count: int = 0
    total_pronunciation_count: int = 0

class ProgressDetail(BaseModel):
    """각 학습 항목별 상세 진척도"""
    goal: int = 0
    achieved: int = 0
    progress: float = 0.0  # 0.0 ~ 1.0 사이의 값

class LearningProgressResponse(BaseModel):
    """/progress 엔드포인트의 최종 응답 모델"""
    overall_progress: float
    conversation: ProgressDetail
    grammar: ProgressDetail
    pronunciation: ProgressDetail
    feedback: str

# 목표 대비 진척도 통계
class ProgressStats(BaseModel):
    conversation_progress: float = 0.0
    grammar_progress: float = 0.0
    pronunciation_progress: float = 0.0

# 학습 통계
class StatisticsResponse(BaseModel):
    overall_statistics: OverallStats
    progress_statistics: Optional[ProgressStats] = None
    feedback: Optional[str] = None