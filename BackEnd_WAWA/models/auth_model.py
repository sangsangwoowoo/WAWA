# '인증' 관련 데이터 형식을 Pydantic 모델로 정의합니다.
from pydantic import BaseModel

# --- 로그인 요청 스키마 ---
class UserLogin(BaseModel):
    username: str
    password: str