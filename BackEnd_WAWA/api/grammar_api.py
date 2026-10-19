# api/grammar_api.py

from fastapi import APIRouter, HTTPException, Depends, Query, Body
from core.dependencies import get_current_user
from core.database import get_db
from supabase import AsyncClient
from models.grammar_model import GrammarHistoryResponse, GrammarStatistics, GrammarSessionCreate, GrammarQuestionFavoriteUpdate
from db import grammar_supabase
from typing import List

router = APIRouter()

# ▼▼▼ [추가] 누락되었던 문법 연습 이력 목록 조회 API ▼▼▼
@router.get("/history", response_model=List[GrammarHistoryResponse])
async def get_grammar_history_route(
        limit: int = 20,
        offset: int = 0,
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """현재 로그인한 사용자의 문법 연습 이력 목록을 조회합니다."""
    try:
        user_id = current_user.get('user_id')
        history = await grammar_supabase.get_grammar_history(db, user_id, limit, offset)
        return history
    except Exception as e:
        print(f"문법 이력 조회 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# 문법 연습 통계 조회 API (변경 없음)
# 문법 연습 통계 조회 API (변경 없음)
@router.get("/statistics", response_model=GrammarStatistics)
async def get_grammar_statistics_route(
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """현재 로그인한 사용자의 문법 연습 통계를 조회합니다."""
    try:
        user_id = current_user.get('user_id')
        stats = await grammar_supabase.get_grammar_statistics(db, user_id)
        return stats
    except Exception as e:
        print(f"문법 통계 조회 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ▼▼▼ [수정] 중복 정의되었던 함수를 하나로 정리 ▼▼▼
# 문법 연습 이력 저장 API
@router.post("/history/add", status_code=200)
async def add_grammar_history_route(
        session_data: GrammarSessionCreate, # 요청 body가 새 모델을 따름
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """현재 로그인한 사용자의 음성 기반 문법 연습 결과를 저장합니다."""
    try:
        user_id = current_user.get('user_id')
        await grammar_supabase.add_grammar_session(db, user_id, session_data) # 이 함수가 새 모델을 사용함
        return {"message": "Grammar practice history saved successfully"}
    except Exception as e:
        print(f"문법 이력 저장 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# 즐겨찾기 상태 업데이트 API
@router.patch("/history/{history_id}/favorite", status_code=200)
async def update_grammar_favorite_status_route(
        history_id: int,
        is_favorite: bool = Query(...),
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db),
):
    """특정 문법 학습 이력의 즐겨찾기 상태를 업데이트합니다."""
    try:
        user_id = current_user.get('user_id')
        updated_item = await grammar_supabase.update_favorite_status(db, user_id, history_id, is_favorite)
        if not updated_item:
            raise HTTPException(status_code=404, detail="History not found or permission denied")
        return {"message": "Favorite status updated successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 즐겨찾기 목록 조회 API
@router.get("/favorites", response_model=List[GrammarHistoryResponse])
async def get_favorite_grammar_history_route(
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """현재 사용자가 즐겨찾기한 문법 이력 목록을 조회합니다."""
    try:
        user_id = current_user.get('user_id')
        favorites = await grammar_supabase.get_favorite_grammar_history(db, user_id)
        return favorites
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/questions/{question_id}/favorite", status_code=200)
async def toggle_grammar_question_favorite_route(
        question_id: str,
        update_data: GrammarQuestionFavoriteUpdate, # 모델이 업데이트되었습니다.
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """특정 문법 문제의 즐겨찾기 상태를 토글합니다."""
    try:
        user_id = current_user.get('user_id')
        # 모델의 dict()를 그대로 전달합니다.
        await grammar_supabase.toggle_question_favorite(
            db, user_id, question_id, update_data.dict()
        )
        return {"message": "Favorite status updated successfully"}
    except Exception as e:
        print(f"문제 즐겨찾기 토글 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ▼▼▼ [추가] 파일 맨 아래에 새로운 API 라우터를 추가하세요 ▼▼▼
@router.get("/questions/favorites", response_model=List[dict])
async def get_favorite_grammar_questions_route(
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """현재 사용자가 즐겨찾기한 문법 '문제' 목록을 조회합니다."""
    try:
        user_id = current_user.get('user_id')
        questions = await grammar_supabase.get_favorite_grammar_questions(db, user_id)
        return questions
    except Exception as e:
        print(f"즐겨찾기 문제 목록 조회 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))