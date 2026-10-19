# models/challenge_model.py

from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime

# --- 챌린지 생성 및 수정 모델 ---
class ChallengeCreate(BaseModel):
    title: str = Field(..., min_length=3, max_length=100)
    description: Optional[str] = Field(None, max_length=1000)
    duration_days: int = Field(..., ge=1, le=365)
    challenge_type: str
    target_value: int

class ChallengeUpdate(BaseModel):
    title: str = Field(..., min_length=3, max_length=100)
    description: Optional[str] = Field(None, max_length=1000)

# --- 챌린지 인증 모델 ---
class SubmissionCreate(BaseModel):
    proof_content: Optional[str] = Field(None, max_length=500)
    proof_image_base64: Optional[str] = Field(None, description="Base64 encoded image data")

# --- API 응답 모델 ---
class ChallengeParticipant(BaseModel):
    user_id: str
    user_name: str
    completed_at: datetime

class ChallengeSubmissionResponse(BaseModel):
    id: int
    user_id: str
    user_name: str
    proof_content: Optional[str]
    proof_image_url: Optional[str]
    status: str
    submitted_at: datetime

class ChallengeResponse(BaseModel):
    id: int
    group_id: int
    creator_id: str
    creator_name: str
    title: str
    description: Optional[str]
    end_date: datetime
    created_at: datetime

    # 이 챌린지를 완료한 참여자 목록
    participants: List[ChallengeParticipant] = []

    # 현재 요청을 보낸 사용자의 완료 여부
    user_has_completed: bool

# (참고) ProgressLogRequest는 이제 사용되지 않습니다.
class ProgressLogRequest(BaseModel):
    log_type: str
    value: int