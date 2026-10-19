# 'LevelTest' 관련 모델에 대한 데이터베이스 CRUD 작업을 정의하는 파일입니다.
from supabase import AsyncClient

# --- 모든 레벨 테스트 문제 조회 ---
async def get_all_questions(db: AsyncClient):
    response = await db.table("level_test_questions").select("*").execute()
    return response.data

# --- 레벨 테스트 결과 생성 ---
async def create_level_test_result(db: AsyncClient, user_id: int, score: int, level: str):
    result_data = {
        "user_id": user_id,
        "score": score,
        "level": level
    }
    response = await db.table("level_test_results").insert(result_data).execute()
    return response.data[0] if response.data else None
