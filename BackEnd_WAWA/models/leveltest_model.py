# '레벨 테스트' 관련 데이터 형식을 Pydantic 모델로 정의합니다.
from pydantic import BaseModel
from typing import List

# --- 레벨 테스트 문제 API 응답 스키마 ---
# 정답(correct_answer) 필드는 제외하여 클라이언트에 노출되지 않도록 합니다.
class LevelTestQuestionResponse(BaseModel):
    id: int
    question_text: str
    difficulty: int

    class Config:
        orm_mode = True

# --- 사용자가 제출하는 개별 답안의 스키마 ---
class UserAnswer(BaseModel):
    question_id: int
    submitted_answer: str

# --- 답안 제출을 위한 전체 요청 스키마 ---
class LevelTestSubmit(BaseModel):
    answers: List[UserAnswer]

# --- 레벨 테스트 결과 API 응답 스키마 ---
class LevelTestResultResponse(BaseModel):
    id: int
    user_id: int
    score: int
    level: str

    class Config:
        orm_mode = True