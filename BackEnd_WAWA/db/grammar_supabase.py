# db/grammar_supabase.py

from supabase import AsyncClient
from typing import List, Dict, Any, Optional
from models.grammar_model import GrammarSessionCreate

# 사용자의 문법 연습 이력 조회
async def get_grammar_history(
        db: AsyncClient, user_id: str, limit: int = 20, offset: int = 0
) -> List[Dict[str, Any]]:
    """사용자의 문법 연습 이력을 최신순으로 조회합니다."""
    response = await db.table('grammar_sessions') \
        .select('id, transcribed_text, corrected_text, grammar_feedback, vocabulary_suggestions, created_at, is_favorite, is_correct') \
        .eq('user_id', user_id) \
        .order('created_at', desc=True) \
        .limit(limit) \
        .offset(offset) \
        .execute()
    return response.data

# 문법 연습 통계 계산
async def get_grammar_statistics(
        db: AsyncClient,
        user_id: str
) -> Dict[str, Any]:
    """사용자의 문법 연습 통계를 계산합니다."""
    # [수정] is_correct 필드를 직접 사용합니다.
    response = await db.table('grammar_sessions') \
        .select('is_correct, created_at') \
        .eq('user_id', user_id) \
        .order('created_at', desc=True) \
        .execute()

    if not response.data:
        return {
            'total_count': 0,
            'correct_count': 0,
            'incorrect_count': 0,
            'accuracy': 0.0,
            'recent_accuracy': None
        }

    history = response.data
    total_count = len(history)

    # [수정] is_correct가 True인 항목의 개수를 셉니다.
    correct_count = sum(1 for item in history if item['is_correct'])
    incorrect_count = total_count - correct_count
    accuracy = (correct_count / total_count * 100) if total_count > 0 else 0.0

    recent_accuracy = None
    if total_count >= 10:
        recent_10 = history[:10]
        recent_correct = sum(1 for item in recent_10 if item['is_correct'])
        recent_accuracy = (recent_correct / 10 * 100)

    return {
        'total_count': total_count,
        'correct_count': correct_count,
        'incorrect_count': incorrect_count,
        'accuracy': accuracy,
        'recent_accuracy': recent_accuracy
    }

# 문법 연습 이력 추가
async def add_grammar_session(
        db: AsyncClient, user_id: str, session_data: GrammarSessionCreate
) -> Dict[str, Any]:
    """grammar_sessions 테이블에 새로운 연습 이력을 추가합니다."""
    response = await db.table('grammar_sessions') \
        .insert({
        'user_id': user_id,
        'transcribed_text': session_data.transcribed_text,
        'corrected_text': session_data.corrected_text,
        'grammar_feedback': session_data.grammar_feedback,
        'vocabulary_suggestions': session_data.vocabulary_suggestions,
        'is_correct': session_data.is_correct # <-- [추가]
    }) \
        .execute()
    return response.data[0]

# 즐겨찾기 상태 업데이트 함수
async def update_favorite_status(
        db: AsyncClient, user_id: str, history_id: int, is_favorite: bool
) -> Optional[Dict[str, Any]]:
    """ID와 사용자 ID가 일치하는 문법 이력의 is_favorite 값을 업데이트합니다."""
    response = await db.table('grammar_sessions') \
        .update({'is_favorite': is_favorite}) \
        .eq('id', history_id) \
        .eq('user_id', user_id) \
        .execute()
    return response.data[0] if response.data else None

# 즐겨찾기 목록 조회 함수
async def get_favorite_grammar_history(
        db: AsyncClient, user_id: str
) -> List[Dict[str, Any]]:
    """사용자가 즐겨찾기한 문법 이력 목록을 조회합니다."""
    response = await db.table('grammar_sessions') \
        .select('id, transcribed_text, corrected_text, grammar_feedback, vocabulary_suggestions, created_at, is_favorite, is_correct') \
        .eq('user_id', user_id) \
        .eq('is_favorite', True) \
        .order('created_at', desc=True) \
        .execute()
    return response.data

async def toggle_question_favorite(
        db: AsyncClient, user_id: str, question_id: str, update_data: dict
) -> None:
    """
    favorite_grammar_questions 테이블에 즐겨찾기 상태를 추가하거나 삭제합니다.
    """
    is_favorite = update_data.get('is_favorite')

    if is_favorite:
        # 즐겨찾기 추가 시, 문제 내용도 함께 저장합니다.
        await db.table('favorite_grammar_questions') \
            .upsert({
            'user_id': user_id,
            'question_id': question_id,
            'question': update_data.get('question'),
            'options': update_data.get('options')
        }, on_conflict='user_id, question_id') \
            .execute()
    else:
        # 즐겨찾기 삭제
        await db.table('favorite_grammar_questions') \
            .delete() \
            .eq('user_id', user_id) \
            .eq('question_id', question_id) \
            .execute()

async def get_favorite_grammar_questions(
        db: AsyncClient, user_id: str
) -> List[Dict[str, Any]]:
    """사용자가 즐겨찾기한 문법 '문제' 목록을 조회합니다."""
    response = await db.table('favorite_grammar_questions') \
        .select('question_id, question, options') \
        .eq('user_id', user_id) \
        .order('created_at', desc=True) \
        .execute()
    return response.data