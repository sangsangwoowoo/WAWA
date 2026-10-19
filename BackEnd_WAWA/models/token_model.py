# '토큰' 관련 데이터 형식을 Pydantic 모델로 정의합니다.
from pydantic import BaseModel

# --- 로그인 성공 시 반환될 전체 토큰 정보 스키마 ---
class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str

# --- 토큰 재발급 성공 시 반환될 Access Token 정보 스키마 ---
class AccessToken(BaseModel):
    access_token: str
    token_type: str

# --- 토큰 재발급을 요청할 때 필요한 Refresh Token 스키마 ---
class RefreshToken(BaseModel):
    refresh_token: str