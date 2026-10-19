# '출석 체크' 관련 데이터 형식을 Pydantic 모델로 정의합니다.
from pydantic import BaseModel
from datetime import date, datetime

# --- 출석 기록 API 응답 스키마 ---
class AttendanceResponse(BaseModel):
    id: int
    user_id: str
    date: date
    created_at: datetime

    class Config:
        orm_mode = True

# --- 출석 통계 API 응답 스키마 ---
class AttendanceStatsResponse(BaseModel):
    total_days: int
    longest_streak: int