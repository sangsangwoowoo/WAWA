# db/plan_supabase.py

import os
from typing import Optional, Dict, Any
from supabase import AsyncClient
from dotenv import load_dotenv

load_dotenv()

async def save_learning_plan_to_db(plan_data: dict, db: AsyncClient):
    try:
        response = await db.table('learning_plans').insert(plan_data).execute()
        return response.data
    except Exception as e:
        print(f"학습 계획 저장 중 오류 발생: {e}")
        raise e

async def get_latest_plan_by_user(user_id: str, db: AsyncClient) -> Optional[Dict[str, Any]]:
    """
    'learning_plans' 테이블에서 특정 사용자의 가장 최근 계획 하나를 조회합니다.
    """
    try:
        response = await db.table("learning_plans") \
            .select("*") \
            .eq("user_id", user_id) \
            .order("created_at", desc=True) \
            .limit(1) \
            .maybe_single() \
            .execute()
        return response.data
    except Exception as e:
        print(f"최신 학습 계획 조회 중 오류 발생: {e}")
        return None

# ▼▼▼ [수정] 이 함수 전체를 아래의 새 코드로 교체합니다. ▼▼▼
async def update_learning_plan_in_db(plan_id: int, update_data: dict, db: AsyncClient) -> Optional[Dict[str, Any]]:
    """
    'learning_plans' 테이블에서 특정 ID의 계획을 업데이트합니다.
    """
    try:
        # 1. 불필요한 키를 제거하고 데이터를 업데이트합니다. (select 없이)
        update_data.pop('id', None)
        update_data.pop('created_at', None)
        update_data.pop('user_id', None)

        await db.table("learning_plans") \
            .update(update_data) \
            .eq("id", plan_id) \
            .execute()

        # 2. 업데이트가 완료된 후, 별도의 쿼리로 해당 데이터를 다시 조회하여 반환합니다.
        response = await db.table("learning_plans") \
            .select("*") \
            .eq("id", plan_id) \
            .single() \
            .execute()

        return response.data

    except Exception as e:
        print(f"학습 계획 업데이트 중 오류 발생: {e}")
        return None
