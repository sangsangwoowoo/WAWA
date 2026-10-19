# models/notification_model.py

from pydantic import BaseModel
from typing import Optional
from datetime import datetime

# --- API 응답에 사용될 알림 정보 스키마 ---
# 클라이언트(앱)에 알림 정보를 보여줄 때 이 형식을 사용합니다.
class NotificationResponse(BaseModel):
    id: int
    user_id: str
    type: str
    content: str
    is_read: bool
    created_at: datetime

    class Config:
        from_attributes = True # DB 모델 객체를 Pydantic 모델로 변환

# --- 알림 설정 스키마 ---
class NotificationSettings(BaseModel):
    """알림 설정 전체 구조를 정의하는 모델"""
    study_notification: bool = True
    marketing_notification: bool = True

class NotificationSettingsUpdate(BaseModel):
    """알림 설정 업데이트(PATCH) 요청을 위한 모델"""
    study_notification: Optional[bool] = None
    marketing_notification: Optional[bool] = None

