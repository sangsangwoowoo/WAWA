from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Body, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from supabase import Client as AsyncClient
from core.database import get_db
from core.dependencies import get_current_user
from db import user_crud
from models import user_model

from db.login_supabase import get_supabase_client
from models.login_model import (
    UserCreate, CharacterUpdate, LanguageSettingUpdate,
    UserProfileUpdate, TokenData, LoginResponse, SocialLoginUrl, UserLevelUpdate,
    UserProfileResponse, CodeExchangeRequest
)
from services import login_service

router = APIRouter()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(user: UserCreate, supabase: AsyncClient = Depends(get_supabase_client)):
    """회원가입"""
    return await login_service.register_user(user, supabase)

@router.post("/create-profile", status_code=status.HTTP_201_CREATED)
async def create_profile_endpoint(
        authorization: str = Header(...),
        supabase: AsyncClient = Depends(get_supabase_client)
):
    """(인증 필요) 사용자 프로필 생성"""
    token = authorization.split(" ")[1]
    return await login_service.create_user_profile(token, supabase)

@router.get("/profile", response_model=UserProfileResponse)
async def get_my_profile(
        authorization: str = Header(...),
        supabase: AsyncClient = Depends(get_supabase_client)
):
    """(인증 필요) 내 프로필 정보 조회"""
    token = authorization.split(" ")[1]
    return await login_service.get_current_user(token=token, supabase=supabase)

@router.post("/login", response_model=LoginResponse)
async def login(
        form_data: OAuth2PasswordRequestForm = Depends(),
        supabase: AsyncClient = Depends(get_supabase_client)
):
    """로그인 (이메일, 비밀번호)"""
    return await login_service.login_for_access_token(form_data, supabase)

@router.get("/login/{provider}", response_model=SocialLoginUrl)
async def social_login(
        provider: Literal["google", "kakao"],
        supabase: AsyncClient = Depends(get_supabase_client)
):
    """소셜 로그인 URL 요청"""
    return await login_service.get_social_login_url(provider, supabase)

@router.post("/exchange-code", response_model=LoginResponse)
async def exchange_code_for_session_endpoint(
        request: CodeExchangeRequest,
        supabase: AsyncClient = Depends(get_supabase_client)
):
    """소셜 로그인 콜백 후 받은 코드를 세션(토큰)으로 교환"""
    return await login_service.exchange_code_for_session(
        auth_code=request.auth_code,
        code_verifier=request.code_verifier,
        supabase=supabase
    )

@router.post("/login/auto", response_model=LoginResponse)
async def auto_login(token_data: TokenData, supabase: AsyncClient = Depends(get_supabase_client)):
    """자동 로그인"""
    # auto_login_with_token이 LoginResponse와 호환되는 딕셔너리를 반환해야 합니다.
    # 서비스 로직에서 반환 값을 LoginResponse 모델에 맞게 조정해야 할 수 있습니다.
    return await login_service.auto_login_with_token(token_data.token, supabase)

@router.post("/update-level")
async def update_level(
        level_update: UserLevelUpdate,
        supabase: AsyncClient = Depends(get_supabase_client)
):
    """사용자 레벨 업데이트 (관리자 또는 시스템용)"""
    return await login_service.update_user_assessed_level(
        email=level_update.email,
        level=level_update.assessed_level,
        supabase=supabase
    )

@router.patch("/update-details")
async def update_details(
        user_update: UserProfileUpdate,
        token: str = Depends(oauth2_scheme),
        supabase: AsyncClient = Depends(get_supabase_client)
):
    """(인증 필요) 소셜 로그인 후 누락된 프로필 정보(이메일, 이름) 업데이트"""
    user_response = await supabase.auth.get_user(token)
    user = user_response.user
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="유효하지 않은 토큰입니다.")
    return await login_service.update_additional_user_info(str(user.id), user_update, supabase)

@router.patch("/update-languages")
async def update_languages(
        language_update: LanguageSettingUpdate,
        token: str = Depends(oauth2_scheme),
        supabase: AsyncClient = Depends(get_supabase_client)
):
    """(인증 필요) 모국어와 학습 언어 업데이트"""
    user_response = await supabase.auth.get_user(token)
    user = user_response.user
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="유효하지 않은 토큰입니다.")
    return await login_service.update_user_languages(str(user.id), language_update, supabase)

@router.patch("/update-character")
async def update_character(
        character_update: CharacterUpdate,
        token: str = Depends(oauth2_scheme),
        supabase: AsyncClient = Depends(get_supabase_client)
):
    """(인증 필요) 선택한 캐릭터 정보 업데이트"""
    user_response = await supabase.auth.get_user(token)
    user = user_response.user
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="유효하지 않은 토큰입니다.")
    return await login_service.update_user_character(str(user.id), character_update, supabase)

@router.post("/check-name")
async def check_name_availability(
        name: str = Body(..., embed=True),
        supabase: AsyncClient = Depends(get_supabase_client)
):
    """이름 중복 검사"""
    # ✨ 수정된 부분: 공백 검사 로직 추가
    if ' ' in name:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="이름에는 공백을 사용할 수 없습니다."
        )

    if not name or len(name.strip()) < 2:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="이름은 2자 이상이어야 합니다.")

    is_available = await login_service.check_name_availability(name.strip(), supabase)
    return {"available": is_available}