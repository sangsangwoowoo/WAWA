# core/dependencies.py

from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from supabase import AsyncClient
from starlette import status
from datetime import datetime

from core.database import get_db
from core import security
from db import user_crud
from jose import JWTError, ExpiredSignatureError
import time

bearer_scheme = HTTPBearer()

async def get_current_user(
        token: HTTPAuthorizationCredentials = Depends(bearer_scheme),
        db: AsyncClient = Depends(get_db)
) -> dict:

    # --- 토큰 검증 ---
    # 이 부분은 이미 성공하는 것을 확인했으므로, 디버그 코드는 제거하거나 두어도 됩니다.
    email = security.get_username_from_token(token.credentials)

    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="토큰이 유효하지 않거나 이메일이 없습니다."
        )

    # --- 데이터베이스 조회 ---
    user = await user_crud.get_user_by_username(db, username=email)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="사용자를 찾을 수 없거나 비활성 계정입니다."
        )
    return user


async def get_current_admin(current_user: dict = Depends(get_current_user)):
    if not current_user.get('is_admin'):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin privileges required")
    return current_user
