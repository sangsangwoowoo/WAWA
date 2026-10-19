# '사용자 프로필' 관련 비즈니스 로직을 처리하는 파일입니다.
from supabase import AsyncClient
from models import user_model
from db import user_crud
from core import security
from fastapi import HTTPException
from typing import Dict, Any
import logging

# --- 사용자 정보 수정 서비스 ---
async def update_user(db: AsyncClient, user_id: str, user_update: user_model.UserUpdate):
    update_data = user_update.dict(exclude_unset=True)
    if "password" in update_data and update_data["password"]:
        hashed_password = security.hash_password(update_data["password"])
        update_data["password"] = hashed_password

    updated = await user_crud.update_user(db=db, user_id=user_id, update_data=update_data)
    if not updated:
        # [수정] 업데이트할 사용자를 찾지 못한 경우 404 예외 발생
        raise HTTPException(status_code=404, detail="사용자 정보를 찾을 수 없어 업데이트에 실패했습니다.")
    return updated

# ▼▼▼ [추가] 비밀번호 변경 서비스 ▼▼▼
async def update_password(db: AsyncClient, user_id: str, pass_update: user_model.PasswordUpdate):
    """
    사용자의 비밀번호를 확인하고 새로운 비밀번호로 업데이트합니다.
    """
    user = await user_crud.get_user(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="사용자 정보를 찾을 수 없습니다.")

    # [수정] 소셜 로그인 사용자에 대한 명확한 안내
    if not user.get('password'):
        raise HTTPException(
            status_code=400,
            detail="소셜 로그인 사용자는 앱 내에서 비밀번호를 변경할 수 없습니다."
        )

    # [수정] 현재 비밀번호 불일치 시 명확한 안내
    if not security.verify_password(pass_update.current_password, user['password']):
        raise HTTPException(status_code=401, detail="현재 비밀번호가 일치하지 않습니다.")

    # [수정] 새 비밀번호와 현재 비밀번호가 같은 경우
    if pass_update.current_password == pass_update.new_password:
        raise HTTPException(status_code=400, detail="새 비밀번호는 현재 비밀번호와 달라야 합니다.")

    try:
        await db.auth.admin.update_user_by_id(user_id, {"password": pass_update.new_password})
        logging.info(f"Supabase Auth 비밀번호 업데이트 성공: {user_id}")
    except Exception as e:
        logging.error(f"Supabase Auth 비밀번호 업데이트 실패: {e}")
        raise HTTPException(status_code=500, detail="비밀번호 변경 중 시스템 오류가 발생했습니다. (Code: AUTH)")

    hashed_password = security.hash_password(pass_update.new_password)
    updated_user = await user_crud.update_password(db=db, user_id=user_id, hashed_password=hashed_password)
    if not updated_user:
        raise HTTPException(status_code=500, detail="비밀번호 변경 중 시스템 오류가 발생했습니다. (Code: DB)")

    logging.info(f"비밀번호 변경 완료: {user_id}")
    # [수정] 반환 데이터에서 민감한 정보(비밀번호) 제거
    return {"message": "비밀번호가 성공적으로 변경되었습니다."}

# ▼▼▼ [추가] 회원 탈퇴 서비스 ▼▼▼
async def delete_account(db: AsyncClient, user_id: str, account_delete: user_model.AccountDelete):
    """
    사용자 비밀번호를 확인하고 계정을 삭제합니다.
    """
    user = await user_crud.get_user(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="삭제할 사용자 계정을 찾을 수 없습니다.")

    # [수정] 비밀번호 불일치 시 명확한 안내
    if not user.get('password') or not security.verify_password(account_delete.password, user['password']):
        raise HTTPException(status_code=401, detail="비밀번호가 일치하지 않아 계정을 삭제할 수 없습니다.")

    try:
        await db.auth.admin.delete_user(user['id'])
    except Exception as e:
        logging.warning(f"Supabase Auth 사용자 삭제 실패 (프로필 삭제는 계속 진행): {e}")

    deleted = await user_crud.delete_user(db, user_id)
    if not deleted:
        raise HTTPException(status_code=500, detail="계정 삭제 처리 중 문제가 발생했습니다.")

    return {"message": "회원 탈퇴가 정상적으로 처리되었습니다."}

async def update_user_name(db: AsyncClient, user_id: str, update_data: dict):
    """이름만 수정하는 서비스"""
    new_name = update_data.get("name")
    if not new_name:
        raise HTTPException(status_code=400, detail="변경할 이름이 제공되지 않았습니다.")

    # 1. 현재 사용자 정보 조회
    current_user = await user_crud.get_user(db, user_id)
    if not current_user:
        raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다.")

    # 2. 현재 이름과 새 이름 비교
    if current_user.get('name') == new_name:
        # 409 Conflict: 요청이 리소스의 현재 상태와 충돌함
        raise HTTPException(status_code=409, detail="현재 이름과 동일한 이름으로는 변경할 수 없습니다.")

    # 3. 이름 변경 진행
    return await user_crud.update_user(db=db, user_id=user_id, update_data=update_data)
