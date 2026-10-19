import os
from supabase import AsyncClient
from dotenv import load_dotenv
from typing import Optional, Dict, Any

load_dotenv()

# ✅ 전역 클라이언트 제거, 대신 함수 파라미터로 받음

async def get_user_data_from_supabase(user_id: str, db: AsyncClient) -> Optional[Dict[str, Any]]:
    """user_account 테이블에서 사용자 데이터를 가져옵니다."""
    try:
        response = await db.table('user_account').select("*").eq('user_id', user_id).single().execute()
        return response.data
    except Exception as e:
        print(f"사용자 데이터를 가져오는 중 오류 발생 {user_id}: {e}")
        return None

async def update_user_learning_goal(user_id: str, goal_data: Dict[str, Any], db: AsyncClient) -> None:
    """user_account 테이블에서 user_id가 일치하는 사용자의 learning_goals를 업데이트합니다."""
    try:
        await db.table('user_account').update({'learning_goals': goal_data}).eq('user_id', user_id).execute()
        print(f"사용자 {user_id}의 학습 목표 업데이트 성공")
    except Exception as e:
        print(f"학습 목표 업데이트 중 오류 발생: {e}")
        raise e

async def add_learning_log_to_user(user_id: str, log_data: Dict[str, Any], db: AsyncClient) -> None:
    """기존 learning_logs에 새로운 로그를 추가하여 업데이트합니다."""
    try:
        # 1. 사용자의 현재 데이터를 가져옵니다.
        user_data = await get_user_data_from_supabase(user_id, db)
        if user_data is None:
            raise Exception("사용자를 찾을 수 없습니다.")

        # 2. 기존 로그 목록을 가져오거나, 없으면 빈 리스트로 시작합니다.
        current_logs = user_data.get('learning_logs', [])
        if current_logs is None:  # DB에 null로 저장된 경우
            current_logs = []

        # 3. 새로운 로그를 목록에 추가합니다.
        current_logs.append(log_data)

        # 4. 업데이트된 전체 로그 목록을 DB에 저장합니다.
        await db.table('user_account').update({'learning_logs': current_logs}).eq('user_id', user_id).execute()
        print(f"사용자 {user_id}의 학습 로그 추가 성공")

    except Exception as e:
        print(f"학습 로그 추가 중 오류 발생: {e}")
        raise e