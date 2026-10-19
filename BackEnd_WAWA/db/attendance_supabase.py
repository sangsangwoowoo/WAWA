# 'Attendance' 모델에 대한 데이터베이스 CRUD 작업을 정의하는 파일입니다.
from supabase import AsyncClient
from datetime import date

# --- 특정 날짜의 출석 기록 조회 ---
async def get_attendance_by_date(db: AsyncClient, user_id: str, attendance_date: date):
    date_str = attendance_date.isoformat()
    response = await db.table("attendances").select("*").eq("user_id", user_id).eq("date", date_str).limit(1).maybe_single().execute()
    return response.data if response else None

# --- 출석 기록 생성 ---
async def create_attendance(db: AsyncClient, user_id: str, attendance_date: date):
    attendance_data = {
        "user_id": user_id,
        "date": attendance_date.isoformat()
    }
    response = await db.table("attendances").insert(attendance_data).execute()
    return response.data[0] if response.data else None

# --- 특정 사용자의 모든 출석 기록 조회 ---
async def get_all_attendances_by_user(db: AsyncClient, user_id: str):
    response = await db.table("attendances").select("*").eq("user_id", user_id).order("date", desc=False).execute()
    return response.data
