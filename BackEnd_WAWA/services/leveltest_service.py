# '레벨 테스트' 관련 비즈니스 로직을 처리하는 파일입니다.
import random
from supabase import AsyncClient
from models import leveltest_model
from db import leveltest_supabase, user_crud

# --- 랜덤 문제 조회 서비스 ---
async def get_random_questions(db: AsyncClient, count: int):
    questions = await leveltest_supabase.get_all_questions(db)
    if not questions:
        return []
    return random.sample(questions, min(count, len(questions)))

# --- 답안 제출 및 채점 서비스 ---
async def process_submission(db: AsyncClient, user_id: int, submission: leveltest_model.LevelTestSubmit):
    all_questions = await leveltest_supabase.get_all_questions(db)
    score = 0
    question_map = {q['id']: q['correct_answer'] for q in all_questions}

    for answer in submission.answers:
        if question_map.get(answer.question_id) == answer.submitted_answer:
            score += 1

    total = len(question_map)
    percentage = (score / total) * 100 if total > 0 else 0

    if percentage < 40:
        level = "beginner"
    elif percentage < 70:
        level = "intermediate"
    else:
        level = "advanced"

    result = await leveltest_supabase.create_level_test_result(
        db=db, user_id=user_id, score=score, level=level
    )

    await user_crud.update_user(db=db, user_id=user_id, update_data={"level": level})

    return result
