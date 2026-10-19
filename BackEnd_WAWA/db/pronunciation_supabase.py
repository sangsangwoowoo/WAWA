from supabase import AsyncClient
from typing import List, Dict, Any, Optional

async def get_pronunciation_history(
        db: AsyncClient,
        user_id: str,
        limit: int = 20,
        offset: int = 0
) -> List[Dict[str, Any]]:
    """사용자의 발음 분석 이력 조회"""
    # ✅ pronunciation_session → pronunciation_sessions
    response = await db.table('pronunciation_analysis_results') \
        .select('*, phoneme_score, pronunciation_sessions!inner(user_id, target_text, session_id)') \
        .eq('pronunciation_sessions.user_id', user_id) \
        .order('created_at', desc=True) \
        .limit(limit) \
        .offset(offset) \
        .execute()

    # 데이터 변환
    history = []
    for item in response.data:
        session = item.pop('pronunciation_sessions')
        history.append({
            **item,
            'session_id': session['session_id'],
            'target_text': session['target_text'],
            'detailed_feedback': item.get('detailed_feedback', []),
            'misstressed_words': item.get('missstressed_word', [])
        })

    return history

async def get_pronunciation_detail(
        db: AsyncClient,
        result_id: str,
        user_id: str
) -> Optional[Dict[str, Any]]:
    """특정 발음 분석 결과 상세 조회"""
    response = await db.table('pronunciation_analysis_results') \
        .select('*, phoneme_score, pronunciation_sessions!inner(user_id, target_text, session_id)') \
        .eq('id', result_id) \
        .eq('pronunciation_sessions.user_id', user_id) \
        .single() \
        .execute()

    if not response.data:
        return None

    item = response.data
    session = item.pop('pronunciation_sessions')

    return {
        **item,
        'session_id': session['session_id'],
        'target_text': session['target_text'],
        'detailed_feedback': item.get('detailed_feedback', []),
        'misstressed_words': item.get('missstressed_word', [])
    }

async def delete_pronunciation_history(
        db: AsyncClient,
        result_id: str,
        user_id: str
) -> bool:
    """발음 분석 이력 삭제"""
    check = await db.table('pronunciation_analysis_results') \
        .select('pronunciation_sessions!inner(user_id)') \
        .eq('id', result_id) \
        .eq('pronunciation_sessions.user_id', user_id) \
        .execute()

    if not check.data:
        raise Exception('삭제 권한이 없습니다.')

    await db.table('pronunciation_analysis_results') \
        .delete() \
        .eq('id', result_id) \
        .execute()

    return True

async def get_pronunciation_statistics(
        db: AsyncClient,
        user_id: str
) -> Dict[str, Any]:
    """발음 분석 통계"""
    response = await db.table('pronunciation_analysis_results') \
        .select('overall_score, pitch_score, rhythm_score, stress_score, fluency_score, phoneme_score, created_at, pronunciation_sessions!inner(user_id)') \
        .eq('pronunciation_sessions.user_id', user_id) \
        .order('created_at', desc=True) \
        .execute()

    if not response.data:
        return {
            'total_count': 0,
            'average_overall': 0.0,
            'average_pitch': 0.0,
            'average_rhythm': 0.0,
            'average_stress': 0.0,
            'average_fluency': 0.0,
            'average_phoneme': 0.0,
            'recent_improvement': None
        }

    scores = response.data
    count = len(scores)

    # 최근 5개와 전체 평균 비교로 개선도 계산
    recent_improvement = None
    if count >= 10:
        recent_5_avg = sum(s['overall_score'] for s in scores[:5]) / 5
        older_5_avg = sum(s['overall_score'] for s in scores[5:10]) / 5
        recent_improvement = recent_5_avg - older_5_avg

    return {
        'total_count': count,
        'average_overall': sum(s['overall_score'] for s in scores) / count,
        'average_pitch': sum(s['pitch_score'] for s in scores) / count,
        'average_rhythm': sum(s['rhythm_score'] for s in scores) / count,
        'average_stress': sum(s['stress_score'] for s in scores) / count,
        'average_fluency': sum(s.get('fluency_score', 0) or 0 for s in scores) / count,
        'average_phoneme': sum(s.get('phoneme_score', 0) or 0 for s in scores) / count,
        'recent_improvement': recent_improvement
    }