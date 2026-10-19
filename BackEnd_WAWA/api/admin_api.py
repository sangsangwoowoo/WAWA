# '관리자' 기능 관련 API 엔드포인트를 정의하는 파일입니다.
from fastapi import APIRouter, Depends
from core.dependencies import get_current_admin

router = APIRouter(prefix="/admin")

# --- 관리자 대시보드 API (예시) ---
@router.get("/dashboard")
async def admin_dashboard(current_admin: dict = Depends(get_current_admin)):
    return {"message": f"Welcome to the admin dashboard, {current_admin['username']}!"}
