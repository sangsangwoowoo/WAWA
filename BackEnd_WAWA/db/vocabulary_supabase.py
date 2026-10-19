# db/vocabulary_supabase.py

from typing import List, Optional

from supabase import AsyncClient

from models import vocabulary_model


# --- Wordbook ---
async def create_wordbook(db: AsyncClient, name: str, user_id: str):
    response = await db.table("wordbooks").insert({"name": name, "user_id": user_id}).execute()
    return response.data[0] if response.data else None

async def get_wordbooks_by_user(db: AsyncClient, user_id: str) -> List[dict]:
    # RPC를 호출하여 단어 개수와 함께 단어장 목록을 가져옵니다.
    response = await db.rpc('get_user_wordbooks_with_count', {'p_user_id': user_id}).execute()
    return response.data

async def get_wordbook_with_words(db: AsyncClient, wordbook_id: int, user_id: str):
    """
    (최종 수정) 단어장 정보와 함께, 1000개 제한을 해결하여 모든 단어 목록을 조회합니다.
    """
    try:
        # 1. 단어장 자체의 정보를 가져옵니다.
        wordbook_response = await db.table("wordbooks").select("*") \
            .eq("id", wordbook_id) \
            .eq("user_id", user_id) \
            .single() \
            .execute()

        if not wordbook_response.data:
            return None

        wordbook_data = wordbook_response.data

        # 2. [핵심] 해당 단어장에 속한 모든 단어를 조회하되, 조회 한도를 5000개로 늘립니다.
        # 여러 줄의 쿼리는 문법 오류 방지를 위해 괄호로 묶습니다.
        words_response = (
            await db.table("user_words")
            .select("*")
            .eq("wordbook_id", wordbook_id)
            .limit(5000)  # 👈 1000개 제한을 5000개로 상향 조정하는 코드
            .order('id', desc=False)
            .execute()
        )

        # 3. 조회된 단어 목록(최대 5000개)을 단어장 정보에 합쳐서 반환합니다.
        wordbook_data['user_words'] = words_response.data
        return wordbook_data

    except Exception as e:
        print(f"### get_wordbook_with_words 오류: {e}")
        return None

# --- UserWord ---
async def add_word_to_wordbook(db: AsyncClient, word: vocabulary_model.UserWordCreate, wordbook_id: int):
    word_data = word.model_dump()
    word_data['wordbook_id'] = wordbook_id
    response = await db.table("user_words").insert(word_data).execute()
    return response.data[0] if response.data else None

async def update_word_details(db: AsyncClient, word_id: int, word_data: dict):
    response = await db.table("user_words").update(word_data).eq("id", word_id).execute()
    return response.data[0] if response.data else None

async def update_word_status(db: AsyncClient, word_id: int, is_memorized: bool):
    response = await db.table("user_words").update({"is_memorized": is_memorized}).eq("id", word_id).execute()
    return response.data[0] if response.data else None

async def delete_word(db: AsyncClient, word_id: int):
    response = await db.table("user_words").delete().eq("id", word_id).execute()
    return response.data

async def add_words_to_wordbook_batch(db: AsyncClient, words: List[dict]):
    """
    (최종 수정) 대용량 단어 리스트를 작은 덩어리(chunk)로 나누어 순차적으로 삽입합니다.
    """
    all_inserted_data = []
    chunk_size = 500  # 한 번에 삽입할 단어 개수 (500개로 설정)

    print(f"--- 총 {len(words)}개의 단어를 {chunk_size}개씩 나누어 저장을 시작합니다. ---")

    for i in range(0, len(words), chunk_size):
        # 전체 단어 리스트를 chunk_size 만큼씩 잘라냅니다.
        chunk = words[i:i + chunk_size]
        print(f"--- {i+1}번째부터 {i+len(chunk)}번째 단어 덩어리 저장 시도... ---")

        try:
            # 잘라낸 덩어리만 데이터베이스에 삽입합니다.
            response = await db.table("user_words").insert(chunk).execute()
            if response.data:
                all_inserted_data.extend(response.data)
            print(f"--- 덩어리 저장 성공. 현재까지 총 {len(all_inserted_data)}개 저장됨. ---")

        except Exception as e:
            # 특정 덩어리에서 오류가 발생해도 멈추지 않고 로그만 남기고 계속 진행합니다.
            print(f"!!! 덩어리 저장 중 오류 발생: {e} !!!")
            print(f"!!! 오류 발생 덩어리 (첫 5개): {chunk[:5]}")

    return all_inserted_data

async def delete_wordbook(db: AsyncClient, wordbook_id: int, user_id: str):
    # ON DELETE CASCADE 옵션 덕분에, 단어장이 삭제되면 관련된 단어들도 자동으로 함께 삭제됩니다.
    response = await db.table("wordbooks").delete().eq("id", wordbook_id).eq("user_id", user_id).execute()
    return response.data

async def update_word_favorite_status(db: AsyncClient, word_id: int, is_favorite: bool):
    response = await db.table("user_words").update({"is_favorite": is_favorite}).eq("id", word_id).execute()
    return response.data[0] if response.data else None

async def get_favorite_words(db: AsyncClient, user_id: str):
    response = await db.table("user_words").select("*, wordbooks!inner(*)").eq(
        "wordbooks.user_id", user_id
    ).eq(
        "is_favorite", True
    ).order('created_at', desc=True).execute()

    return response.data

async def get_word_stats_by_user(db: AsyncClient, user_id: str):
    response = await db.rpc('get_user_word_stats', {'p_user_id': user_id}).single().execute()
    return response.data

async def get_all_words_by_user(db: AsyncClient, user_id: str, status: Optional[str] = None):
    query = db.table("user_words").select("*, wordbooks!inner(*)").eq("wordbooks.user_id", user_id)

    if status == 'memorized':
        query = query.eq('is_memorized', True)
    elif status == 'not_memorized':
        query = query.eq('is_memorized', False)

    response = await query.order('id', desc=False).execute()
    return response.data

# --- 검색 및 단어 상세 조회 ---
async def search_user_words(db: AsyncClient, user_id: str, query: str):
    response = await db.table("user_words").select("*, wordbooks!inner(*)") \
        .eq("wordbooks.user_id", user_id) \
        .or_(f"word.ilike.%{query}%,definition.ilike.%{query}%") \
        .order("created_at", desc=True) \
        .execute()
    return response.data

async def get_user_word_detail(db: AsyncClient, user_id: str, word_id: int):
    response = await db.table("user_words").select("*, wordbooks!inner(*)") \
        .eq("wordbooks.user_id", user_id) \
        .eq("id", word_id) \
        .single() \
        .execute()
    return response.data