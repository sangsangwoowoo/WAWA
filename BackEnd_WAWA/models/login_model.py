from typing import Optional, Dict

from pydantic import BaseModel, EmailStr, ConfigDict, field_validator


# Pydantic V2에서는 Union 타입을 | (파이프)로 표현하는 것을 권장합니다.
# from typing import Union -> Optional[str] 또는 str | None 으로 대체

class UserCreate(BaseModel):
    email: EmailStr
    password: str
    name: str
    is_admin: bool = False

    @field_validator('password')
    def validate_password_length(cls, v):
        # UTF-8 바이트 길이 체크
        if len(v.encode('utf-8')) > 72:
            raise ValueError('비밀번호는 72바이트를 초과할 수 없습니다')
        # (선택사항) 최소 길이도 여기서 검사할 수 있습니다.
        if len(v) < 8:
            raise ValueError('비밀번호는 8자 이상이어야 합니다')
        return v

class UserUpdate(BaseModel):
    email: Optional[EmailStr] = None
    password: Optional[str] = None
    is_admin: Optional[bool] = None

class UserProfileUpdate(BaseModel):
    email: Optional[EmailStr] = None
    name: Optional[str] = None

# ▼▼▼ [수정] Token과 LoginResponse를 하나로 통합합니다. ▼▼▼
class LoginResponse(BaseModel):
    """로그인 성공 시 반환하는 통합 데이터 모델"""
    access_token: str
    token_type: str
    assessed_level: Optional[str] = None
    is_admin: Optional[bool] = None
    beginner_mode: bool = False

class SocialLoginUrl(BaseModel):
    url: str
    code_verifier: str

class UserLevelUpdate(BaseModel):
    email: str
    assessed_level: str

class TokenData(BaseModel):
    token: str

class UserProfileResponse(BaseModel):
    """API가 반환하는 사용자 프로필 정보 모델"""
    user_id: str
    email: EmailStr
    name: str
    assessed_level: Optional[str] = None
    learning_goals: Optional[Dict] = None
    created_at: Optional[str] = None
    is_admin: Optional[bool] = None
    native_language: Optional[str] = None
    target_language: Optional[str] = None
    selected_character_name: Optional[str] = None
    selected_character_image: Optional[str] = None
    beginner_mode: bool = False
    points: int = 0

    model_config = ConfigDict(from_attributes=True)

class LanguageSettingUpdate(BaseModel):
    """언어 설정 업데이트 모델"""
    native_language: str
    target_language: str

class CharacterUpdate(BaseModel):
    """캐릭터 설정 업데이트 모델"""
    selected_character_name: str
    selected_character_image: str

class NameCheckRequest(BaseModel):
    name: str

class NameCheckResponse(BaseModel):
    available: bool

class CodeExchangeRequest(BaseModel):
    auth_code: str
    code_verifier: str