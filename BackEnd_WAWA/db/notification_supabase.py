# db/notification_supabase.py

from supabase import AsyncClient
from typing import Dict, Any

async def create_notification(db: AsyncClient, user_id: str, notif_type: str, content: str) -> Dict[str, Any]:
    """
    Supabase 'notifications' 테이블에 새로운 알림을 추가합니다.

    Args:
        db (AsyncClient): Supabase 비동기 클라이언트
        user_id (str): 알림을 받을 사용자의 UUID
        notif_type (str): 알림 종류
        content (str): 알림 내용

    Returns:
        Dict[str, Any]: 생성된 알림 데이터
    """
    try:
        response = await db.table('notifications').insert({
            'user_id': user_id,
            'type': notif_type,
            'content': content
        }).execute()

        print(f"알림 생성 성공: User {user_id}, Type {notif_type}")
        return response.data[0] if response.data else None
    except Exception as e:
        print(f"알림 생성 실패: {e}")
        # 실제 운영 환경에서는 로깅 라이브러리를 사용하는 것이 좋습니다.
        return None

async def get_notifications_by_user(db: AsyncClient, user_id: str, skip: int = 0, limit: int = 20):
    """특정 사용자의 알림 목록을 최신순으로 정렬하여 조회합니다."""
    response = await db.table("notifications").select("*").eq("user_id", user_id).order("created_at", desc=True).range(skip, skip + limit - 1).execute()
    return response.data

# --- 특정 알림 ID로 조회 ---
async def get_notification_by_id(db: AsyncClient, notification_id: int):
    """ID를 기준으로 특정 알림 하나를 조회합니다."""
    response = await db.table("notifications").select("*").eq("id", notification_id).maybe_single().execute()
    return response.data if response else None

# --- 알림 읽음 처리 ---
async def mark_notification_as_read(db: AsyncClient, notification_id: int):
    """특정 알림의 is_read 상태를 true로 변경합니다."""
    response = await db.table("notifications").update({"is_read": True}).eq("id", notification_id).execute()
    return response.data[0] if response.data else None
