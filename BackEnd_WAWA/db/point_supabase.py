# db/point_supabase.py
from uuid import UUID
from supabase import AsyncClient # AsyncClient 타입을 명시하기 위해 import

# supabase 클라이언트를 인자로 받고, 함수를 비동기(async)로 변경
async def update_points_and_log(db: AsyncClient, user_id: UUID, amount: int, reason: str):
    """RPC를 호출하여 포인트를 변경하고 내역을 기록합니다."""

    result = await db.rpc('handle_point_change', {
        'user_id_input': str(user_id),
        'change_amount_input': amount,
        'reason_text': reason
    }).execute()

    # ▼▼▼ [핵심 수정] RPC 반환값이 리스트 형태일 경우, 실제 숫자 값만 추출하여 반환하도록 수정합니다. ▼▼▼
    if result.data and isinstance(result.data, list) and len(result.data) > 0:
        # 반환값이 [{'handle_point_change': 1200}] 형태일 경우
        if isinstance(result.data[0], dict):
            # 딕셔너리의 첫 번째 값(실제 포인트)을 반환합니다.
            return list(result.data[0].values())[0]
        # 반환값이 [1200] 형태일 경우
        else:
            return result.data[0]

    # 그 외의 경우, 원래대로 반환
    return result.data

async def get_point_transactions_by_user(db: AsyncClient, user_id: UUID) -> list:
    """특정 사용자의 포인트 거래 내역을 최신순으로 조회합니다."""
    response = await db.table("point_history") \
        .select("id, created_at, change_amount, reason") \
        .eq("user_id", str(user_id)) \
        .order("created_at", desc=True) \
        .execute()
    # ▲▲▲ [수정 완료] ▲▲▲
    return response.data if response.data else []