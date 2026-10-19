from pydantic import BaseModel, field_validator
from typing import List, Optional, Dict, Any, Union
from datetime import datetime
import json

class PronunciationHistoryResponse(BaseModel):
    id: str  # ✅ int → str (UUID)
    session_id: str
    target_text: str
    overall_score: float
    pitch_score: float
    rhythm_score: float
    stress_score: float
    fluency_score: Optional[float] = None
    confidence: Optional[float] = None
    rate_status: Optional[str] = None
    fluency_status: Optional[str] = None
    phoneme_score: Optional[float] = None
    misstressed_words: Optional[List[str]] = None
    detailed_feedback: List[str]
    suggestions: List[str]
    created_at: datetime

    # ✅ JSON 문자열을 리스트로 변환하는 validator 추가
    @field_validator('detailed_feedback', 'suggestions', mode='before')
    @classmethod
    def parse_json_list(cls, v):
        if isinstance(v, str):
            try:
                return json.loads(v)
            except:
                return []
        return v if v else []

    @field_validator('misstressed_words', mode='before')
    @classmethod
    def parse_misstressed_words(cls, v):
        if isinstance(v, str):
            try:
                return json.loads(v)
            except:
                return None
        return v

class PronunciationHistoryDetail(PronunciationHistoryResponse):
    phoneme_scores: Optional[Dict[str, Any]] = None

    @field_validator('phoneme_scores', mode='before')
    @classmethod
    def parse_phoneme_scores(cls, v):
        if isinstance(v, str):
            try:
                return json.loads(v)
            except:
                return None
        return v

class PronunciationStatistics(BaseModel):
    total_count: int
    average_overall: float
    average_pitch: float
    average_rhythm: float
    average_stress: float
    average_fluency: float
    average_phoneme: Optional[float] = 0.0
    recent_improvement: Optional[float] = None
