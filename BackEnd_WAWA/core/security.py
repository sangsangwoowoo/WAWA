from datetime import datetime, timedelta
from jose import JWTError, jwt
from passlib.context import CryptContext
from core import config
import os
import logging
from dotenv import load_dotenv

load_dotenv()

# ▼▼▼ [수정] "bcrypt" -> "sha512_crypt"로 변경 ▼▼▼
pwd_context = CryptContext(
    schemes=["sha512_crypt", "bcrypt"], # 1. sha512_crypt를 기본값으로
    deprecated="auto",

    # 2. bcrypt 관련 설정은 그대로 둡니다 (기존 해시 검증용)
    bcrypt__rounds=12,
    bcrypt__ident="2b"
)
# ▲▲▲ [수정 완료] ▲▲▲


# .env 파일의 SUPABASE_JWT_SECRET 값을 가져옵니다.
JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET")
ALGORITHM = config.ALGORITHM

# --- Password Hashing ---
def hash_password(password: str) -> str:
    """비밀번호를 해싱합니다. (sha512_crypt 사용)"""
    try:
        # ▼▼▼ [수정] 72바이트 제한 로직(if, password=...) 삭제 ▼▼▼
        # if len(password.encode('utf-8')) > 72:
        #     password = password[:72]
        #     logging.warning("비밀번호가 72바이트를 초과하여 잘렸습니다")

        hashed = pwd_context.hash(password)
        logging.info("비밀번호 해싱 성공 (sha512_crypt)")
        return hashed
    except Exception as e:
        logging.error(f"비밀번호 해싱 실패: {e}")
        raise

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """평문 비밀번호와 해시를 비교합니다."""
    try:
        # ▼▼▼ [수정] 72바이트 제한 로직(if, plain_password=...) 삭제 ▼▼▼
        # passlib가 해시 타입(sha512_crypt or bcrypt)을
        # 자동으로 감지하고 올바른 방식으로 검증합니다.

        # if len(plain_password.encode('utf-8')) > 72:
        #     plain_password = plain_password[:72]
        #     logging.warning("검증할 비밀번호가 72바이트를 초과하여 잘렸습니다")

        result = pwd_context.verify(plain_password, hashed_password)
        logging.info(f"비밀번호 검증 완료 - 결과: {result}")
        return result
    except Exception as e:
        logging.error(f"비밀번호 검증 오류: {e}")
        return False

# --- JWT Token ---
def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=config.ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, JWT_SECRET, algorithm=ALGORITHM)


def create_refresh_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=config.REFRESH_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire})
    # ▼▼▼ [수정] JWT_SECRET 변수를 사용합니다. ▼▼▼
    return jwt.encode(to_encode, JWT_SECRET, algorithm=config.ALGORITHM)


def get_username_from_token(token: str):
    try:
        # 👈 jose.jwt.decode 사용 확인
        payload = jwt.decode(
            token,
            JWT_SECRET,
            algorithms=[ALGORITHM],
            audience='authenticated' # 👈 audience 옵션도 여기에 포함
        )
        return payload.get("email")
    except JWTError:
        return None