# services/vocabulary_service.py

from fastapi import HTTPException
from supabase import AsyncClient
import re
from db import vocabulary_supabase
from models import vocabulary_model
import httpx
import asyncio
from googletrans import Translator
import os
from dotenv import load_dotenv

# .env 파일에서 환경 변수를 로드합니다.
load_dotenv()
MERRIAM_WEBSTER_API_KEY = os.getenv("MERRIAM_WEBSTER_API_KEY")

# --- Wordbook ---
async def create_new_wordbook(db: AsyncClient, name: str, user_id: str):
    return await vocabulary_supabase.create_wordbook(db, name, user_id)

async def get_user_wordbooks(db: AsyncClient, user_id: str):
    wordbooks = await vocabulary_supabase.get_wordbooks_by_user(db, user_id)
    # Pydantic 모델에 맞게 데이터 가공
    return [
        vocabulary_model.WordbookResponse(
            id=wb['id'],
            user_id=wb['user_id'],
            name=wb['name'],
            created_at=wb['created_at'],
            word_count=wb['word_count']
        ) for wb in wordbooks
    ]

# --- UserWord ---
async def add_new_word(db: AsyncClient, word: vocabulary_model.UserWordCreate, wordbook_id: int):
    return await vocabulary_supabase.add_word_to_wordbook(db, word, wordbook_id)

async def update_word_content(db: AsyncClient, word_id: int, word_update_data: vocabulary_model.UserWordContentUpdate):
    update_data = word_update_data.model_dump()
    return await vocabulary_supabase.update_word_details(db, word_id, update_data)

async def get_full_wordbook(db: AsyncClient, wordbook_id: int, user_id: str):
    wordbook_data = await vocabulary_supabase.get_wordbook_with_words(db, wordbook_id, user_id)
    if not wordbook_data:
        # [수정] 단어장이 없을 경우, None 대신 404 예외 발생
        raise HTTPException(status_code=404, detail="요청한 단어장을 찾을 수 없습니다.")

    wordbook_data['words'] = wordbook_data.get('user_words', [])
    return vocabulary_model.WordbookDetailResponse.model_validate(wordbook_data)


async def toggle_word_memorized(db: AsyncClient, word_id: int, is_memorized: bool):
    return await vocabulary_supabase.update_word_status(db, word_id, is_memorized)

async def remove_word_from_wordbook(db: AsyncClient, word_id: int):
    # [수정] 삭제 결과에 따라 처리
    deleted_word = await vocabulary_supabase.delete_word(db, word_id)
    if not deleted_word:
        raise HTTPException(status_code=404, detail="삭제할 단어를 찾을 수 없습니다.")
    return deleted_word

async def add_new_words_batch(db: AsyncClient, words_in: vocabulary_model.UserWordBatchCreate, wordbook_id: int):
    """
    (단순화된 버전) 앱에서 받은 단어 목록을 DB에 그대로 전달하여 한 번에 저장합니다.
    """
    words_to_insert = []
    for word in words_in.words:
        word_dict = word.model_dump()
        word_dict['wordbook_id'] = wordbook_id
        words_to_insert.append(word_dict)

    return await vocabulary_supabase.add_words_to_wordbook_batch(db, words_to_insert)


async def delete_user_wordbook(db: AsyncClient, wordbook_id: int, user_id: str):
    # [수정] Supabase 함수가 삭제된 행의 수를 반환한다고 가정하고, 결과에 따라 처리
    deleted_wordbook = await vocabulary_supabase.delete_wordbook(db, wordbook_id, user_id)
    if not deleted_wordbook:
        # 삭제가 실패했거나, 대상이 없거나, 권한이 없는 경우
        raise HTTPException(status_code=404, detail="단어장을 삭제할 수 없거나 찾을 수 없습니다.")
    return deleted_wordbook

async def toggle_word_favorite(db: AsyncClient, word_id: int, is_favorite: bool):
    return await vocabulary_supabase.update_word_favorite_status(db, word_id, is_favorite)

async def get_all_favorite_words(db: AsyncClient, user_id: str):
    return await vocabulary_supabase.get_favorite_words(db, user_id)

async def get_word_stats(db: AsyncClient, user_id: str):
    return await vocabulary_supabase.get_word_stats_by_user(db, user_id)

async def get_all_words(db: AsyncClient, user_id: str, status: str | None):
    return await vocabulary_supabase.get_all_words_by_user(db, user_id, status)

# --- 검색 및 상세 조회 ---
async def search_user_words(db: AsyncClient, user_id: str, query: str):
    return await vocabulary_supabase.search_user_words(db, user_id, query)

async def get_word_detail(db: AsyncClient, user_id: str, word_id: int):
    return await vocabulary_supabase.get_user_word_detail(db, user_id, word_id)

def is_korean(text: str) -> bool:
    """간단한 정규식으로 한글 포함 여부 확인"""
    return bool(re.search("[\uac00-\ud7a3]", text))

# ▼▼▼ [수정] search_word_online 함수 전체를 아래 코드로 교체 ▼▼▼
async def search_word_online(query: str):
    """
    (수정) Merriam-Webster API와 Google Translate를 이용해 단어 정보를 검색하고 가공합니다.
    한글 검색을 지원하고, 영단어 검색 실패 시 대체 로직을 추가합니다.
    """
    if not MERRIAM_WEBSTER_API_KEY:
        raise HTTPException(status_code=500, detail="Merriam-Webster API 키가 서버에 설정되지 않았습니다.")

    translator = Translator()
    original_query = query
    english_query = query.lower()
    korean_meaning_of_query = ""

    # 1. 입력된 쿼리가 한글인지, 영어인지 판별하고 검색 준비
    if is_korean(original_query):
        try:
            translated = await asyncio.to_thread(translator.translate, original_query, src='ko', dest='en')
            english_query = translated.text.lower()
            korean_meaning_of_query = original_query
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"'{original_query}' 번역 중 오류 발생: {e}")
    else:
        try:
            translated = await asyncio.to_thread(translator.translate, original_query, src='en', dest='ko')
            korean_meaning_of_query = translated.text
        except Exception:
            korean_meaning_of_query = ""

    # 2. 영단어로 Merriam-Webster API 검색 시도
    api_url = f"https://www.dictionaryapi.com/api/v3/references/collegiate/json/{english_query}?key={MERRIAM_WEBSTER_API_KEY}"
    data = None
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(api_url, timeout=10.0)
            response.raise_for_status()
            api_data = response.json()
            if api_data and isinstance(api_data[0], dict):
                data = api_data
        except Exception:
            # API 호출 실패 시, data는 None으로 유지되고 아래 대체 로직으로 넘어갑니다.
            pass

    # 3. API 검색 결과 처리
    # [CASE 1] Merriam-Webster 검색 성공 시
    if data:
        entry = data[0]
        word = entry.get("hwi", {}).get("hw", english_query).replace("*", "")
        pronunciation = ""
        if entry.get("hwi", {}).get("prs"):
            pronunciation = entry["hwi"]["prs"][0].get("mw", "")
        part_of_speech = entry.get("fl", "")

        pos_map = {"noun": "명사", "verb": "동사", "adjective": "형용사", "adverb": "부사", "preposition": "전치사", "conjunction": "접속사", "pronoun": "대명사", "interjection": "감탄사"}
        korean_pos = pos_map.get(part_of_speech, part_of_speech)

        formatted_definition = korean_meaning_of_query
        if korean_pos and korean_meaning_of_query:
            formatted_definition = f"({korean_pos}) {korean_meaning_of_query}"

        example = ""
        if entry.get("def"):
            for sseq_item in entry["def"][0].get("sseq", []):
                for sense_item in sseq_item:
                    if sense_item[0] == "sense":
                        dt_list = sense_item[1].get("dt", [])
                        for dt in dt_list:
                            if dt[0] == "vis":
                                example_text = dt[1][0].get("t")
                                if example_text:
                                    example = re.sub(r'\{.*?\}', '', example_text).strip()
                                    break
                    if example: break
                if example: break

        return {
            "word": word,
            "definition": formatted_definition,
            "pronunciation": f"/{pronunciation}/" if pronunciation else "",
            "english_example": example,
        }

    # [CASE 2] Merriam-Webster 검색 실패 시 (대체 번역 로직)
    else:
        if korean_meaning_of_query:
            return {
                "word": english_query,
                "definition": f"(뜻) {korean_meaning_of_query}",
                "pronunciation": "", # 발음기호 정보 없음
                # ▼▼▼ [수정] 예문이 없을 때 사용자에게 표시될 메시지 ▼▼▼
                "english_example": "예문을 찾을 수 없습니다.",
            }
        else:
            raise HTTPException(status_code=404, detail=f"'{original_query}'에 대한 정보를 찾을 수 없습니다.")