# '인증' 관련 API 엔드포인트를 정의하는 파일입니다.
from fastapi import APIRouter, Depends, HTTPException, status
from supabase import AsyncClient # 👈 Session 대신 AsyncClient를 import
from core.database import get_db
from models import auth_model, user_model, token_model
from services import auth_service

router = APIRouter(prefix="/auth")

# --- 회원가입 API ---
@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register_user(
        user_create: user_model.UserCreate,
        db: AsyncClient = Depends(get_db)
):
    user = await auth_service.register_new_user(db=db, user_create=user_create)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username already exists",
        )
    return {"message": "User registered successfully", "username": user['username']}

# --- 로그인 API ---
@router.post("/login", response_model=token_model.Token)
async def login_for_access_token(
        login_data: auth_model.UserLogin,
        db: AsyncClient = Depends(get_db)
):
    tokens = await auth_service.authenticate_user(
        db=db, username=login_data.username, password=login_data.password
    )
    if not tokens:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return tokens

# --- 토큰 재발급 API ---
@router.post("/refresh", response_model=token_model.AccessToken)
async def refresh_access_token(
        refresh_request: token_model.RefreshToken,
        db: AsyncClient = Depends(get_db)
):
    new_token = await auth_service.refresh_token(db=db, refresh_token=refresh_request.refresh_token)
    if not new_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
        )
    return new_token
