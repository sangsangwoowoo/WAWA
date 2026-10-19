# '출석 체크' 관련 비즈니스 로직을 처리하는 파일입니다.
from supabase import AsyncClient
from db import attendance_supabase
from fastapi import HTTPException
from datetime import date, timedelta

# --- 출석 체크 서비스 ---
async def mark_attendance(db: AsyncClient, user_id: str):
    today = date.today()
    existing = await attendance_supabase.get_attendance_by_date(db, user_id=user_id, attendance_date=today)
    if existing:
        raise HTTPException(status_code=409, detail="오늘은 이미 출석체크를 완료했습니다.")
    return await attendance_supabase.create_attendance(db, user_id=user_id, attendance_date=today)


# --- 전체 출석 기록 조회 서비스 ---
async def get_user_attendance_history(db: AsyncClient, user_id: str):
    return await attendance_supabase.get_all_attendances_by_user(db, user_id=user_id)

# --- 출석 통계 계산 서비스 ---
async def calculate_stats(db: AsyncClient, user_id: str):
    records = await attendance_supabase.get_all_attendances_by_user(db, user_id=user_id)
    if not records:
        return {"total_days": 0, "longest_streak": 0}

    total_days = len(records)
    streak = 0
    max_streak = 0

    # Supabase는 날짜를 문자열로 반환하므로 date 객체로 변환합니다.
    sorted_dates = sorted([date.fromisoformat(r['date']) for r in records])

    if sorted_dates:
        streak = 1
        max_streak = 1
        for i in range(1, len(sorted_dates)):
            if sorted_dates[i] == sorted_dates[i-1] + timedelta(days=1):
                streak += 1
            else:
                streak = 1
            max_streak = max(max_streak, streak)
    return {"total_days": total_days, "longest_streak": max_streak}
