# '인증' 관련 비즈니스 로직을 처리하는 파일입니다.
from supabase import AsyncClient
from core import security
from db import user_crud
from models import user_model

# --- 신규 사용자 등록 서비스 ---
async def register_new_user(db: AsyncClient, user_create: user_model.UserCreate):
    db_user = await user_crud.get_user_by_username(db, username=user_create.username)
    if db_user:
        return None

    hashed_password = security.hash_password(user_create.password)

    return await user_crud.create_user(db=db, user=user_create, hashed_password=hashed_password)

# --- 사용자 인증 서비스 ---
async def authenticate_user(db: AsyncClient, username: str, password: str):
    user = await user_crud.get_user_by_username(db, username)

    # user가 딕셔너리 형태로 반환되므로 키로 접근합니다.
    if not user or not security.verify_password(password, user['password']):
        return None

    access_token = security.create_access_token(data={"sub": user['username']})
    refresh_token = security.create_refresh_token(data={"sub": user['username']})

    return {"access_token": access_token, "refresh_token": refresh_token, "token_type": "bearer"}

# --- 토큰 재발급 서비스 ---
async def refresh_token(db: AsyncClient, refresh_token: str):
    username = security.get_username_from_token(refresh_token)
    if not username:
        return None

    user = await user_crud.get_user_by_username(db, username)
    if not user:
        return None

    access_token = security.create_access_token(data={"sub": user['username']})
    return {"access_token": access_token, "token_type": "bearer"}
