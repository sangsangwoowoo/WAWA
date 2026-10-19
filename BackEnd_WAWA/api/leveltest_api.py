# '레벨 테스트' 관련 API 엔드포인트를 정의하는 파일입니다.
from fastapi import APIRouter, Depends, HTTPException
from supabase import AsyncClient # 👈 Session 대신 AsyncClient를 import
from typing import List

from core.database import get_db
from core.dependencies import get_current_user
from models import leveltest_model
from services import leveltest_service

router = APIRouter(prefix="/level-test")

# --- 레벨 테스트 문제 목록 조회 API ---
@router.get("/questions", response_model=List[leveltest_model.LevelTestQuestionResponse])
async def get_test_questions(db: AsyncClient = Depends(get_db)):
    questions = await leveltest_service.get_random_questions(db=db, count=10)
    if not questions:
        raise HTTPException(status_code=404, detail="No level test questions found")
    return questions

# --- 레벨 테스트 답안 제출 API ---
@router.post("/submit", response_model=leveltest_model.LevelTestResultResponse)
async def submit_test_answers(
        submission: leveltest_model.LevelTestSubmit,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user),
):
    result = await leveltest_service.process_submission(
        db=db, user_id=current_user['id'], submission=submission
    )
    return result
