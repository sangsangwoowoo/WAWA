# models/vocabulary_model.py

from pydantic import BaseModel, ConfigDict
from typing import Optional, List
from datetime import datetime

# --- UserWord ---
class UserWordBase(BaseModel):
    word: str
    definition: str
    pronunciation: Optional[str] = None
    english_example: Optional[str] = None
    is_memorized: bool = False
    is_favorite: bool = False

class UserWordCreate(UserWordBase):
    pass

# ▼▼▼ [ADD CLASS] 여러 단어를 리스트로 받기 위한 모델을 추가합니다. ▼▼▼
class UserWordBatchCreate(BaseModel):
    words: List[UserWordBase]

class UserWordUpdate(BaseModel):
    is_memorized: bool

class UserWordContentUpdate(BaseModel):
    word: str
    definition: str
    pronunciation: Optional[str] = None
    english_example: Optional[str] = None

class UserWordResponse(UserWordBase):
    id: int
    wordbook_id: int
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


# --- Wordbook ---
class WordbookBase(BaseModel):
    name: str

class WordbookCreate(WordbookBase):
    pass

class WordbookResponse(WordbookBase):
    id: int
    user_id: str
    created_at: datetime
    # 단어장 조회 시 단어 개수도 함께 반환
    word_count: Optional[int] = 0

    model_config = ConfigDict(from_attributes=True)

class WordbookDetailResponse(WordbookResponse):
    # 단어장 상세 조회 시 단어 목록 포함
    words: List[UserWordResponse] = []
