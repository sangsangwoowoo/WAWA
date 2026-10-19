# api/notification_api.py

from fastapi import APIRouter, Depends, status, HTTPException
from supabase import AsyncClient
from typing import List

from core.database import get_db
from core.dependencies import get_current_user # 사용자 본인 인증
from models import notification_model
from services import notification_service

router = APIRouter()

# --- 내 알림 설정 조회 API ---
@router.get("/settings", response_model=notification_model.NotificationSettings)
async def get_my_notification_settings(
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    """현재 로그인한 사용자의 알림 설정을 조회합니다."""
    user_id = current_user.get('user_id')
    return await notification_service.get_settings_for_user(db, user_id)

# --- 내 알림 설정 수정 API ---
@router.patch("/settings", response_model=notification_model.NotificationSettings)
async def update_my_notification_settings(
        settings_update: notification_model.NotificationSettingsUpdate,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    """현재 로그인한 사용자의 알림 설정을 업데이트합니다."""
    user_id = current_user.get('user_id')
    updated_settings = await notification_service.update_settings_for_user(db, user_id, settings_update)
    if updated_settings is None:
        raise HTTPException(status_code=500, detail="설정 업데이트에 실패했습니다.")
    return updated_settings

# --- 내 알림 목록 조회 API ---
@router.get("/", response_model=List[notification_model.NotificationResponse])
async def read_my_notifications(
        skip: int = 0,
        limit: int = 20,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    """현재 로그인한 사용자의 알림 목록을 최신순으로 가져옵니다."""
    user_id = current_user.get('user_id')
    return await notification_service.get_all_notifications_for_user(db, user_id, skip, limit)

# --- 알림 읽음 처리 API ---
@router.patch("/{notification_id}/read", response_model=notification_model.NotificationResponse)
async def mark_notification_read(
        notification_id: int,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user) # 본인의 알림만 처리하도록 인증
):
    """특정 알림을 '읽음' 상태로 변경합니다."""
    updated_notification = await notification_service.mark_as_read(db, notification_id, current_user['user_id'])
    if not updated_notification:
        raise HTTPException(status_code=404, detail="알림을 찾을 수 없거나 권한이 없습니다.")
    return updated_notification
