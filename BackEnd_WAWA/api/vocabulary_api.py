# api/vocabulary_api.py

from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from supabase import AsyncClient

from core.database import get_db
from core.dependencies import get_current_user
from db import vocabulary_supabase
from models import vocabulary_model
from services import vocabulary_service

router = APIRouter()

# --- 단어장(Wordbook) 관련 API ---

@router.post("/wordbooks", response_model=vocabulary_model.WordbookResponse, status_code=status.HTTP_201_CREATED)
async def create_wordbook(
        wordbook_in: vocabulary_model.WordbookCreate,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get('user_id')
    return await vocabulary_service.create_new_wordbook(db, wordbook_in.name, user_id)

@router.get("/wordbooks", response_model=List[vocabulary_model.WordbookResponse])
async def get_my_wordbooks(
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get('user_id')
    return await vocabulary_service.get_user_wordbooks(db, user_id)

@router.get("/wordbooks/{wordbook_id}", response_model=vocabulary_model.WordbookDetailResponse)
async def get_wordbook_details(
        wordbook_id: int,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get('user_id')
    wordbook = await vocabulary_service.get_full_wordbook(db, wordbook_id, user_id)
    if not wordbook:
        raise HTTPException(status_code=404, detail="단어장을 찾을 수 없습니다.")
    return wordbook

# --- 단어(UserWord) 관련 API ---

@router.post("/wordbooks/{wordbook_id}/words", response_model=vocabulary_model.UserWordResponse, status_code=status.HTTP_201_CREATED)
async def add_word(
        wordbook_id: int,
        word_in: vocabulary_model.UserWordCreate,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    # TODO: 사용자가 해당 단어장의 소유자인지 확인하는 로직 추가

    # 클라이언트가 보낸 데이터를 받아 서비스 레이어로 전달해 저장만 수행합니다.
    new_word = await vocabulary_service.add_new_word(db, word_in, wordbook_id)
    if not new_word:
        raise HTTPException(status_code=400, detail="단어 추가에 실패했습니다.")

    return new_word

@router.put("/words/{word_id}", response_model=vocabulary_model.UserWordResponse)
async def update_word_content(
        word_id: int,
        word_in: vocabulary_model.UserWordContentUpdate, # 1번에서 만든 모델 사용
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    # TODO: 사용자가 해당 단어의 소유자인지 확인하는 로직 추가
    updated_word = await vocabulary_service.update_word_content(db, word_id, word_in)
    if not updated_word:
        raise HTTPException(status_code=404, detail="수정할 단어를 찾을 수 없습니다.")
    return updated_word

@router.patch("/words/{word_id}", response_model=vocabulary_model.UserWordResponse)
async def update_word(
        word_id: int,
        word_update: vocabulary_model.UserWordUpdate,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    # TODO: 사용자가 해당 단어의 소유자인지 확인하는 로직 추가
    return await vocabulary_service.toggle_word_memorized(db, word_id, word_update.is_memorized)

@router.delete("/words/{word_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_word(
        word_id: int,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    # TODO: 사용자가 해당 단어의 소유자인지 확인하는 로직 추가
    await vocabulary_service.remove_word_from_wordbook(db, word_id)
    return

@router.post("/wordbooks/{wordbook_id}/words/batch", status_code=status.HTTP_201_CREATED)
async def add_words_batch(
        wordbook_id: int,
        words_in: vocabulary_model.UserWordBatchCreate,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    # TODO: 사용자가 해당 단어장의 소유자인지 확인하는 로직 추가

    # 서비스 함수를 직접 호출하고 작업이 끝날 때까지 기다립니다.
    await vocabulary_service.add_new_words_batch(db, words_in, wordbook_id)

    # 작업 완료 후 성공 메시지를 반환합니다.
    return {"message": f"{len(words_in.words)}개의 단어가 성공적으로 추가되었습니다."}


@router.delete("/wordbooks/{wordbook_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_wordbook(
        wordbook_id: int,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get('user_id')
    result = await vocabulary_service.delete_user_wordbook(db, wordbook_id, user_id)
    if not result:
        raise HTTPException(status_code=404, detail="삭제할 단어장을 찾을 수 없거나 권한이 없습니다.")
    return

@router.patch("/words/{word_id}/favorite", response_model=vocabulary_model.UserWordResponse)
async def update_word_favorite(
        word_id: int,
        is_favorite: bool, # 간단한 토글을 위해 body 대신 query parameter 사용
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    # TODO: 사용자가 해당 단어의 소유자인지 확인하는 로직 추가
    word = await vocabulary_service.toggle_word_favorite(db, word_id, is_favorite)
    if not word:
        raise HTTPException(status_code=404, detail="단어를 찾을 수 없습니다.")
    return word

@router.get("/favorites", response_model=List[vocabulary_model.UserWordResponse])
async def get_favorites(
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get('user_id')
    return await vocabulary_service.get_all_favorite_words(db, user_id)

@router.get("/stats", response_model=dict)
async def get_stats(
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get('user_id')
    # 서비스 계층을 거치지 않고 직접 호출 (또는 서비스에 추가)
    stats = await vocabulary_supabase.get_word_stats_by_user(db, user_id)
    return stats

@router.get("/words", response_model=List[vocabulary_model.UserWordResponse])
async def get_all_words(
        status: Optional[str] = None, # 'memorized', 'not_memorized'
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get('user_id')
    # 서비스 계층을 거치지 않고 직접 호출 (또는 서비스에 추가)
    return await vocabulary_supabase.get_all_words_by_user(db, user_id, status)

@router.get("/analysis", response_model=dict)
async def get_vocabulary_analysis(
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get('user_id')
    stats = await vocabulary_supabase.get_word_stats_by_user(db, user_id)
    if not stats:
        return {
            "total_count": 0,
            "memorized_count": 0,
            "not_memorized_count": 0,
            "review_accuracy": 0.0,
        }
    return stats

# --- 단어 검색 API ---
@router.get("/search", response_model=List[vocabulary_model.UserWordResponse])
async def search_words(
        query: str,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get("user_id")
    return await vocabulary_service.search_user_words(db, user_id, query)


# --- 단일 단어 상세 조회 API ---
@router.get("/words/{word_id}/detail", response_model=vocabulary_model.UserWordResponse)
async def get_word_detail(
        word_id: int,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get("user_id")
    word = await vocabulary_service.get_word_detail(db, user_id, word_id)
    if not word:
        raise HTTPException(status_code=404, detail="단어를 찾을 수 없습니다.")
    return word

@router.get("/word-search-online", response_model=dict)
async def search_word_online_endpoint(
        query: str,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    """
    외부 사전 API(dictionaryapi.dev)를 통해 단어의 상세 정보를 검색하고 번역합니다.
    """
    if not query:
        raise HTTPException(status_code=400, detail="검색할 단어를 입력해주세요.")

    try:
        # 서비스 계층의 새 함수를 호출
        word_data = await vocabulary_service.search_word_online(query)
        return word_data
    except HTTPException as e:
        # 서비스에서 발생한 HTTPException을 그대로 클라이언트에 전달
        raise e
    except Exception as e:
        # 그 외 예상치 못한 오류 처리
        raise HTTPException(status_code=500, detail=f"단어 검색 중 서버 오류 발생: {str(e)}")