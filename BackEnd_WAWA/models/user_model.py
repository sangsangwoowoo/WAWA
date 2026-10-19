# '사용자' 기능과 관련된 데이터 형식을 Pydantic 모델로 정의하는 파일입니다.
from typing import Optional

from pydantic import BaseModel, Field, validator


class UserSettingsRequest(BaseModel):
    beginner_mode: Optional[bool] = None
    selected_character_name: Optional[str] = None
    selected_character_image: Optional[str] = None

# --- 사용자 생성을 위한 요청 스키마 ---
# API를 통해 사용자를 생성할 때 받아들일 필드를 정의합니다.
class UserCreate(BaseModel):
    username: str
    password: str
    is_admin: bool = False

# --- 사용자 정보 수정을 위한 요청 스키마 ---
# 모든 필드가 Optional이므로, 클라이언트는 수정하고 싶은 필드만 요청에 포함할 수 있습니다.
class UserUpdate(BaseModel):
    username: Optional[str] = None
    password: Optional[str] = None
    native_language: Optional[str] = None
    learning_language: Optional[str] = None

# --- API 응답에 사용될 사용자 정보 스키마 ---
# 클라이언트에게 반환할 사용자 정보의 구조를 정의합니다.
# password 필드가 없으므로, API 응답에 절대 포함되지 않습니다.
class UserResponse(BaseModel):
    # ▼▼▼ [수정] id 타입을 str으로 변경 (UUID 대응) ▼▼▼
    id: str
    username: str
    is_admin: bool
    is_active: bool
    native_language: Optional[str] = None
    learning_language: Optional[str] = None
    level: Optional[str] = None # level이 없을 수도 있으므로 Optional로 변경

    # ▼▼▼ [추가] beginner_mode 필드를 여기에 추가합니다. ▼▼"
    beginner_mode: bool = Field(default=False)

    # ▼▼▼ [추가] UserResponse가 모든 필드를 다 포함하지 않을 수 있으므로,
    # orm_mode 대신 다른 필드를 추가합니다.
    name: Optional[str] = None
    user_id: Optional[str] = None
    learning_goals: Optional[dict] = None
    selected_character_name: Optional[str] = None
    selected_character_image: Optional[str] = None
    points: int


    class Config:
        from_attributes = True

class UserNameUpdate(BaseModel):
    name: str

# 비밀번호 변경 요청 모델
class PasswordUpdate(BaseModel):
    current_password: str = Field(..., description="현재 비밀번호")
    new_password: str = Field(..., min_length=8, max_length=72, description="새 비밀번호 (8-72자)")

    @validator('new_password')
    def validate_password_length(cls, v):
        # UTF-8 바이트 길이 체크
        if len(v.encode('utf-8')) > 72:
            raise ValueError('비밀번호는 72바이트를 초과할 수 없습니다')
        return v

# 회원 탈퇴 요청 모델
class AccountDelete(BaseModel):
    password: str = Field(..., description="계정 확인을 위한 비밀번호")