import os
import hashlib
import base64
from urllib.parse import urlencode
from fastapi import HTTPException
from fastapi.security import OAuth2PasswordRequestForm
from supabase import Client as AsyncClient

from models.login_model import UserCreate
from gotrue.errors import AuthApiError
from .performance_monitor import measure_performance
from models.login_model import UserProfileUpdate, LanguageSettingUpdate, CharacterUpdate
import logging
from core import security
from db import user_crud
import traceback

logger = logging.getLogger(__name__)

async def check_name_availability(name: str, supabase: AsyncClient) -> bool:
    """user_account 테이블에서 이름이 이미 존재하는지 확인합니다."""
    try:
        response = await supabase.table("user_account").select("user_id").eq("name", name).limit(1).execute()
        return not response.data
    except Exception as e:
        logger.error(f"이름 확인 중 오류 발생: {e}")
        return False

@measure_performance("회원가입")
async def register_user(user: UserCreate, supabase: AsyncClient):
    try:
        logging.info(f"=== 회원가입 시작: {user.email} ===")
        if ' ' in user.name:
            raise HTTPException(
                status_code=400,
                detail="이름에는 공백을 사용할 수 없습니다."
            )

        existing = await user_crud.get_user_by_username(supabase, user.email)
        if existing:
            raise HTTPException(status_code=409, detail="이미 가입된 이메일입니다.")

        auth_response = await supabase.auth.sign_up({
            "email": user.email,
            "password": user.password,
        })

        if not auth_response.user or not auth_response.session:
            raise HTTPException(status_code=400, detail="회원가입 처리 중 문제가 발생했습니다. 입력 정보를 확인해주세요.")

        user_id = str(auth_response.user.id)
        hashed_password = security.hash_password(user.password)

        await user_crud.create_user(
            db=supabase, user_id=user_id, email=user.email,
            name=getattr(user, 'name', user.email.split('@')[0]),
            hashed_password=hashed_password, is_admin=False
        )

        logging.info("=== 회원가입 성공 ===")
        return {
            "access_token": auth_response.session.access_token, "token_type": "bearer",
            "user": {"user_id": user_id, "email": user.email, "name": getattr(user, 'name', user.email.split('@')[0])}
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"회원가입 중 예외 발생: {str(e)}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail="알 수 없는 오류가 발생했습니다. 잠시 후 다시 시도해주세요.")


@measure_performance("프로필 생성")
async def create_user_profile(token: str, supabase: AsyncClient):
    try:
        logging.info(f"=== 프로필 생성 시작 ===")
        user_response = await supabase.auth.get_user(token)
        logging.info(f"User response: {user_response}")
        if not user_response or not user_response.user:
            raise HTTPException(status_code=401, detail="유효하지 않은 토큰입니다")

        user = user_response.user
        user_id = str(user.id)
        logging.info(f"사용자 ID: {user_id}")

        existing = await user_crud.get_user(supabase, user_id)
        if existing:
            logging.info("프로필이 이미 존재합니다")
            return {"message": "프로필이 이미 존재합니다", "user": existing}
        # ... (프로필 생성 로직) ...
    except Exception as e:
        logging.error(f"=== 프로필 생성 오류: {e} ===")
        logging.error(f"스택 트레이스:\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=str(e))

# ▼▼▼ [핵심 수정] 로그인 함수 ▼▼▼
@measure_performance("로그인")
async def login_for_access_token(form_data: OAuth2PasswordRequestForm, supabase: AsyncClient):
    """
    로그인 실패 시, '아이디 또는 비밀번호 오류'로 명확하게 안내합니다.
    """
    try:
        print(f"--- 로그인 시도: {form_data.username} ---")
        res = await supabase.auth.sign_in_with_password({
            "email": form_data.username,
            "password": form_data.password
        })

        if res.session and res.user and res.user.email:
            print(f"--- Supabase 인증 성공: {res.user.email} ---")
            profile_response = await supabase.table("user_account").select("assessed_level, is_admin, beginner_mode").eq("email", res.user.email).maybe_single().execute()

            assessed_level, is_admin, beginner_mode = None, False, False
            if profile_response and profile_response.data:
                assessed_level = profile_response.data.get("assessed_level")
                is_admin = profile_response.data.get("is_admin", False)
                beginner_mode = profile_response.data.get("beginner_mode", False)
            else:
                print("--- 경고: 'user_account' 테이블에 해당 유저의 프로필이 없습니다. ---")

            return {"access_token": res.session.access_token, "token_type": "bearer", "assessed_level": assessed_level, "is_admin": is_admin, "beginner_mode": beginner_mode}

        # 정상적으로는 여기까지 오지 않지만, 만약의 경우를 대비한 방어 코드
        raise HTTPException(status_code=401, detail="로그인에 실패했습니다. 다시 시도해주세요.")

    except AuthApiError as e:
        # Supabase가 예상대로 인증 오류를 발생시키는 경우
        logger.error(f"Supabase 인증 오류 (AuthApiError): {e.message}")
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 잘못되었습니다.")

    except Exception as e:
        # [핵심 수정]
        # AuthApiError가 아닌 다른 오류가 발생했을 때,
        # 오류 메시지에 'invalid login credentials'가 포함되어 있는지 확인하여
        # 이것이 인증 실패 때문인지, 아니면 정말 다른 서버 문제인지 구분합니다.
        error_message = str(e).lower()
        if "invalid login credentials" in error_message:
            logger.error(f"Supabase 인증 오류 (generic catch): {e}")
            raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 잘못되었습니다.")

        # 인증과 관련 없는 다른 모든 오류는 500 서버 오류로 처리합니다.
        logger.error(f"로그인 중 알 수 없는 오류 발생: {e}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail="로그인 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.")


@measure_performance("프로필 조회")
async def get_current_user(token: str, supabase: AsyncClient):
    """JWT 토큰으로 사용자를 확인하고, DB에서 직접 모든 프로필 정보를 조회합니다."""
    try:
        # 1. 토큰으로 supabase.auth의 user 객체를 가져옵니다.
        user_response = await supabase.auth.get_user(token)
        user = user_response.user
        if not user or not user.id:
            raise HTTPException(status_code=401, detail="인증 정보가 유효하지 않습니다. 다시 로그인해주세요.")

        # 2. [가장 확실한 방법] 컬럼 이름을 직접 나열하는 대신, 와일드카드(*)를 사용하여
        #    'user_account' 테이블의 모든 정보를 한 번에 조회합니다.
        #    이 방법은 컬럼명 오타로 인한 오류 가능성을 원천적으로 차단합니다.
        profile_response = await supabase.table("user_account") \
            .select("*") \
            .eq("user_id", str(user.id)) \
            .single() \
            .execute()

        if profile_response.data:
            # 3. 조회된 데이터를 그대로 반환합니다.
            return profile_response.data

        # 프로필 정보가 없는 경우
        raise HTTPException(status_code=404, detail="사용자 프로필을 찾을 수 없습니다.")

    except HTTPException:
        # HTTPException은 그대로 다시 발생시킵니다.
        raise
    except Exception as e:
        # 그 외 모든 예상치 못한 오류를 처리합니다.
        logger.error(f"프로필 조회 중 오류: {e}")
        raise HTTPException(status_code=500, detail="프로필을 불러오는 중 문제가 발생했습니다.")


@measure_performance("평가 레벨 업데이트")
async def update_user_assessed_level(email: str, level: str, supabase: AsyncClient):
    """사용자의 평가 레벨을 이메일 기준으로 업데이트합니다."""
    try:
        # 👇 [디버깅 로그 추가] 레벨 업데이트가 어떤 값으로 시도되는지 확인합니다.
        print(f"--- 레벨 업데이트 시도: email={email}, level={level} ---")
        await supabase.table("user_account").update({"assessed_level": level}).eq("email", email).execute()
        print("--- 레벨 업데이트 성공 ---")
        return {"message": "사용자 레벨이 성공적으로 업데이트되었습니다."}
    except Exception as e:
        print(f"### 레벨 업데이트 중 오류 발생: {e} ###")
        raise HTTPException(status_code=500, detail=f"사용자 레벨 업데이트 중 오류 발생: {str(e)}")

@measure_performance("프로필 인증")
async def auto_login_with_token(token: str, supabase: AsyncClient):
    """JWT 토큰으로 사용자를 인증하고, 성공 시 'ok' 상태와 프로필을 반환합니다."""
    try:
        user_response = await supabase.auth.get_user(token)
        user = user_response.user
        if not user or not user.id: # [수정] user.id로 체크
            raise Exception("유효하지 않은 토큰입니다.")

        # ▼▼▼ [핵심 수정] RPC 호출 대신, 사용자의 모든 프로필 정보를 직접 조회하도록 변경합니다. ▼▼▼
        profile_response = await supabase.table("user_account") \
            .select("*") \
            .eq("user_id", str(user.id)) \
            .single() \
            .execute()

        if profile_response.data:
            profile_data = profile_response.data
            print(f"--- 자동 로그인 프로필 데이터: {profile_data} ---")
            return {"status": "ok", "user_profile": profile_data}
        else:
            raise Exception("프로필을 찾을 수 없습니다.")
    except Exception as e:
        logger.warning(f"자동 로그인 실패: {e}")
        return {"status": "error", "message": str(e)}

@measure_performance("소셜 로그인 URL 생성")
async def get_social_login_url(provider: str, supabase: AsyncClient) -> dict:
    # 1. code_verifier를 직접 생성합니다. (충분히 무작위적인 안전한 문자열)
    code_verifier = base64.urlsafe_b64encode(os.urandom(40)).decode("utf-8").rstrip("=")

    # 2. code_verifier를 SHA256으로 해시하여 code_challenge를 생성합니다.
    code_challenge = hashlib.sha256(code_verifier.encode("utf-8")).digest()
    code_challenge = base64.urlsafe_b64encode(code_challenge).decode("utf-8").rstrip("=")

    # 3. Supabase 인증 URL을 직접 구성합니다.
    supabase_url = os.getenv("SUPABASE_URL")
    params = {
        "provider": provider,
        # ▼▼▼ [수정!] "io.supabase.wawa..." 대신 1단계에서 정한 '공통 주소'로 변경 ▼▼▼
        "redirect_to": "com.songhyoeun.learningapp://auth/callback", # 예시: "com.wawa.app://auth/callback"
        "code_challenge": code_challenge,
        "code_challenge_method": "s256",
    }

    # ❗️ 중요: supabase.auth.sign_in_with_oauth 대신 URL을 직접 만듭니다.
    auth_url = f"{supabase_url}/auth/v1/authorize?{urlencode(params)}"

    print(f"Manually generated {provider} URL: {auth_url}")
    print(f"Generated Code Verifier: {code_verifier}")

    # 4. URL과 함께 code_verifier를 반환합니다.
    return {"url": auth_url, "code_verifier": code_verifier}

@measure_performance("추가 정보 업데이트")
async def update_additional_user_info(user_id: str, user_update: UserProfileUpdate, supabase: AsyncClient):
    """사용자 추가 정보 업데이트 시 발생할 수 있는 오류들을 세분화하여 처리합니다."""
    try:
        update_data = user_update.model_dump(exclude_unset=True)
        if not update_data:
            raise HTTPException(status_code=400, detail="업데이트할 정보가 없습니다.")

        if "email" in update_data:
            existing_user = await supabase.table("user_account").select("user_id").eq("email", update_data["email"]).neq("user_id", user_id).maybe_single().execute()
            if existing_user.data:
                # [수정] 이메일 중복 시 409 Conflict 사용
                raise HTTPException(status_code=409, detail="이미 사용 중인 이메일입니다.")

        result = await supabase.table("user_account").update(update_data).eq("user_id", user_id).execute()

        if not result.data:
            # [수정] 사용자를 찾지 못한 경우 404 Not Found 사용
            raise HTTPException(status_code=404, detail="업데이트할 사용자를 찾을 수 없습니다.")

        return {"message": "사용자 정보가 성공적으로 업데이트되었습니다."}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"추가 정보 업데이트 중 오류: {e}")
        raise HTTPException(status_code=500, detail="정보 업데이트 중 문제가 발생했습니다.")

@measure_performance("소셜 로그인 처리")
async def handle_social_callback(provider: str, code: str, supabase: AsyncClient):
    """소셜 로그인 콜백 처리 - 이메일 없이도 진행"""
    try:
        auth_response = await supabase.auth.exchange_code_for_session({
            "auth_code": code
        })

        if not auth_response.session or not auth_response.user:
            raise HTTPException(status_code=400, detail="세션 생성 실패")

        user = auth_response.user
        user_id = str(user.id)

        # 카카오는 닉네임만 제공, 이메일은 제공하지 않음
        nickname = user.user_metadata.get("full_name") or \
                   user.user_metadata.get("name") or \
                   user.user_metadata.get("preferred_username") or \
                   f"user_{user_id[:8]}"

        # 임시 이메일 생성 (실제 이메일 아님)
        temp_email = f"kakao_{user_id}@temp.placeholder"

        # 기존 사용자 확인
        existing = await supabase.table("user_account") \
            .select("user_id, email, name") \
            .eq("user_id", user_id) \
            .maybe_single() \
            .execute()

        if not existing.data:
            # 신규 사용자 생성
            await supabase.table("user_account").insert({
                "user_id": user_id,
                "email": temp_email,
                "name": nickname,
                "is_admin": False
            }).execute()
            print(f"신규 카카오 사용자: {nickname} (임시이메일: {temp_email})")

        return {
            "access_token": auth_response.session.access_token,
            "token_type": "bearer",
            "needs_additional_info": True  # 항상 추가 정보 필요
        }

    except Exception as e:
        print(f"카카오 로그인 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@measure_performance("언어 설정 업데이트")
async def update_user_languages(
        user_id: str,
        language_update: LanguageSettingUpdate,
        supabase: AsyncClient
):
    """사용자의 모국어와 학습 언어를 업데이트합니다."""
    try:
        await supabase.table("user_account").update({
            "native_language": language_update.native_language,
            "target_language": language_update.target_language
        }).eq("user_id", user_id).execute()

        print(f"언어 설정 업데이트 성공: {user_id}")
        return {"message": "언어 설정이 성공적으로 업데이트되었습니다."}
    except Exception as e:
        print(f"언어 설정 업데이트 오류: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"언어 설정 업데이트 중 오류 발생: {str(e)}"
        )

@measure_performance("캐릭터 설정 업데이트")
async def update_user_character(
        user_id: str,
        character_update: CharacterUpdate,
        supabase: AsyncClient
):
    """사용자의 선택한 캐릭터를 업데이트합니다."""
    try:
        await supabase.table("user_account").update({
            "selected_character_name": character_update.selected_character_name,
            "selected_character_image": character_update.selected_character_image
        }).eq("user_id", user_id).execute()

        print(f"캐릭터 설정 업데이트 성공: {user_id} - {character_update.selected_character_name}")
        return {"message": "캐릭터가 성공적으로 선택되었습니다."}
    except Exception as e:
        print(f"캐릭터 설정 업데이트 오류: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"캐릭터 설정 중 오류 발생: {str(e)}"
        )

async def exchange_code_for_session(auth_code: str, code_verifier: str, supabase: AsyncClient): # code_verifier 파라미터 추가
    """전달받은 auth_code와 code_verifier를 사용해 Supabase로부터 세션을 받아옵니다."""
    try:
        # Supabase에 auth_code와 code_verifier를 모두 보내 세션을 요청합니다.
        res = await supabase.auth.exchange_code_for_session({
            "auth_code": auth_code,
            "code_verifier": code_verifier # 추가된 파라미터
        })

        if res.session and res.user:
            print(f"--- 코드 교환 성공: {res.user.email} ---")

            # 일반 로그인 성공 시와 동일하게 프로필 정보를 조회합니다.
            profile_response = await supabase.table("user_account").select("assessed_level, is_admin, beginner_mode").eq("email", res.user.email).maybe_single().execute()

            assessed_level, is_admin, beginner_mode = None, False, False
            if profile_response and profile_response.data:
                assessed_level = profile_response.data.get("assessed_level")
                is_admin = profile_response.data.get("is_admin", False)
                beginner_mode = profile_response.data.get("beginner_mode", False)

            # LoginResponse 모델에 맞춰 데이터를 반환합니다.
            return {
                "access_token": res.session.access_token,
                "token_type": "bearer",
                "assessed_level": assessed_level,
                "is_admin": is_admin,
                "beginner_mode": beginner_mode
            }

        raise HTTPException(status_code=400, detail="유효하지 않은 인증 코드입니다.")

    except AuthApiError as e:
        logger.error(f"코드 교환 중 인증 오류: {e.message}")
        raise HTTPException(status_code=401, detail="인증 코드 교환에 실패했습니다.")
    except Exception as e:
        logger.error(f"코드 교환 중 알 수 없는 오류: {e}")
        raise HTTPException(status_code=500, detail="세션 생성 중 서버 오류가 발생했습니다.")