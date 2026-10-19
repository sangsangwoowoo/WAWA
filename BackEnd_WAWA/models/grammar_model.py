# models/grammar_model.py

from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

class GrammarHistoryResponse(BaseModel):
    id: int
    transcribed_text: str
    corrected_text: str
    grammar_feedback: Optional[List[str]] = []
    vocabulary_suggestions: Optional[List[str]] = []
    created_at: datetime
    is_favorite: Optional[bool] = False
    is_correct: bool # <-- [추가]

class GrammarSessionCreate(BaseModel):
    transcribed_text: str
    corrected_text: str
    grammar_feedback: Optional[List[str]] = []
    vocabulary_suggestions: Optional[List[str]] = []
    is_correct: bool # <-- [추가]

class GrammarStatistics(BaseModel):
    total_count: int
    correct_count: int
    incorrect_count: int
    accuracy: float
    recent_accuracy: Optional[float] = None

class GrammarQuestionFavoriteUpdate(BaseModel):
    is_favorite: bool
    question: Optional[str] = None
    options: Optional[dict] = None