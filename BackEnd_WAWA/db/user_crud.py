# db/user_crud.py

import logging
from typing import Dict, Any, Optional

from supabase import AsyncClient


# --- 사용자 조회 (Username/Email 기준) ---
async def get_user_by_username(db: AsyncClient, username: str):
    """
    'user_account' 테이블에서 이메일을 기준으로 활성 사용자를 안전하게 조회합니다.
    """
    try:
        response = await db.from_("user_account").select("*").eq("email", username).maybe_single().execute()

        if not response or not response.data:
            return None

        user_data = response.data

        if user_data.get('is_active'):
            return user_data
        else:
            return None

    except Exception as e:
        print(f"사용자 조회 중 오류 발생: {e}")
        return None

# --- 사용자 조회 (ID 기준) ---
async def get_user(db: AsyncClient, user_id: str):
    """
    (수정됨) 사용자 정보를 조회할 때 실제 DB 컬럼명(target_language)을 사용합니다.
    """
    try:
        # 1. select 구문에서 'learning_language'를 실제 컬럼명인 'target_language'로 변경합니다.
        #    'level'도 'assessed_level'일 수 있으므로 두 가능성을 모두 조회합니다.
        response = await db.table("user_account").select(
            "user_id, "
            "email, "
            "name, "
            "is_admin, "
            "is_active, "
            "native_language, "
            "target_language, "  # ◀◀◀ learning_language -> target_language 로 수정
            "assessed_level, "   # ◀◀◀ level 대신 assessed_level 조회
            "beginner_mode, "
            "learning_goals, "
            "selected_character_name, "
            "selected_character_image, "
            "points"
        ).eq("user_id", user_id).limit(1).single().execute()

        if response.data:
            user_data = response.data

            # 2. Pydantic 모델(UserResponse)이 기대하는 필드명으로 데이터를 매핑해줍니다.
            user_data['id'] = user_data.get('user_id')
            user_data['username'] = user_data.get('email')
            # 'target_language' 값을 'learning_language' 키에 복사
            user_data['learning_language'] = user_data.get('target_language')
            # 'assessed_level' 값을 'level' 키에 복사
            user_data['level'] = user_data.get('assessed_level')

            return user_data

        return None

    except Exception as e:
        logging.error(f"get_user 조회 중 오류 발생: {e}")
        return None

# --- 사용자 생성 ---
async def create_user(db: AsyncClient, user_id: str, email: str, name: str, hashed_password: str, is_admin: bool):
    try:
        logging.info(f"=== create_user 함수 시작 ===")

        user_data = {
            "user_id": user_id,
            "email": email,
            "name": name,
            "password": hashed_password,
            "is_admin": is_admin
        }

        logging.info(f"삽입할 데이터: {user_data}")

        # ⚠️ 여기를 수정! insert → upsert
        response = await db.table("user_account").upsert(user_data).execute()

        logging.info(f"DB 응답: {response}")

        return response.data[0] if response.data else None

    except Exception as e:
        logging.error(f"=== create_user 오류 ===")
        logging.error(f"오류: {str(e)}")
        import traceback
        logging.error(f"스택 트레이스:\n{traceback.format_exc()}")
        raise

# --- 사용자 수정 ---
async def update_user(db: AsyncClient, user_id: str, update_data: dict):  # 👈 int → str로 변경
    # 👇 실제 컬럼명으로 변경 (예: user_id)
    response = await db.table("user_account").update(update_data).eq("user_id", user_id).execute()
    return response.data[0] if response.data else None

async def update_password(db: AsyncClient, user_id: str, hashed_password: str):
    """
    사용자의 해싱된 비밀번호를 데이터베이스에 직접 업데이트합니다.
    """
    response = await db.table("user_account").update({"password": hashed_password}).eq("user_id", user_id).execute()
    return response.data[0] if response.data else None

# 사용자 삭제 (회원 탈퇴) 함수
async def delete_user(db: AsyncClient, user_id: str) -> bool:
    """
    user_id를 기준으로 'user_account' 테이블에서 사용자를 삭제합니다.
    """
    try:
        response = await db.from_("user_account").delete().eq("user_id", user_id).execute()
        # 삭제가 성공적으로 이루어지면 response.data에 해당 데이터가 포함됩니다.
        if response.data:
            return True
        return False
    except Exception as e:
        logging.error(f"사용자 삭제 중 오류 발생: {e}")
        return False

async def get_notification_settings(db: AsyncClient, user_id: str) -> Optional[Dict[str, Any]]:
    """user_account 테이블에서 사용자의 알림 설정을 조회합니다."""
    response = await db.table("user_account").select("notification_settings").eq("user_id", user_id).single().execute()
    return response.data.get("notification_settings") if response.data else None

async def update_notification_settings(db: AsyncClient, user_id: str, settings: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """user_account 테이블에서 사용자의 알림 설정을 업데이트합니다."""
    response = await db.table("user_account").update({"notification_settings": settings}).eq("user_id", user_id).execute()
    if response.data:
        return response.data[0].get("notification_settings")
    return None

async def update_user_settings(db: AsyncClient, user_id: str, settings: Dict) -> Optional[Dict]:
    """사용자 ID를 기준으로 특정 설정 값을 업데이트하고, 업데이트된 전체 프로필을 반환합니다."""
    print("\n--- [CRUD DEBUG] update_user_settings 함수가 호출되었습니다. ---")
    print(f"[CRUD DEBUG] 전달받은 user_id: {user_id} (타입: {type(user_id)})")
    print(f"[CRUD DEBUG] 전달받은 settings: {settings}")

    try:
        # 1. 데이터를 업데이트하는 쿼리를 실행합니다.
        print(f"[CRUD DEBUG] user_account 테이블에서 user_id='{user_id}'인 행을 다음 데이터로 업데이트 시도: {settings}")
        update_response = await db.table("user_account").update(settings).eq("user_id", user_id).execute()

        # [핵심] Supabase로부터 받은 실제 응답을 확인합니다.
        print(f"[CRUD DEBUG] Supabase UPDATE 응답 (Raw): {update_response}")

        if not update_response.data:
            print("[CRUD DEBUG] 경고: UPDATE 응답의 'data' 필드가 비어있습니다. 업데이트된 행이 없을 수 있습니다 (user_id 불일치 의심).")

        # 2. 업데이트 후, 확인을 위해 사용자 정보를 다시 조회합니다.
        print(f"[CRUD DEBUG] 확인을 위해 user_id='{user_id}'인 행을 다시 조회합니다...")
        select_response = await db.table("user_account").select("*").eq("user_id", user_id).single().execute()
        print(f"[CRUD DEBUG] Supabase SELECT 응답 (Raw): {select_response}")

        print("--- [CRUD DEBUG] update_user_settings 함수가 정상적으로 종료되었습니다. ---\n")
        return select_response.data

    except Exception as e:
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        print(f"!!! [CRUD DEBUG] update_user_settings 함수에서 심각한 오류 발생: {e}")
        import traceback
        traceback.print_exc()
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n")
        return None