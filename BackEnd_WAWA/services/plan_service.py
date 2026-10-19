# services/plan_service.py

from models.plan_model import LearningPlanRequest, LearningPlanInternal, DirectPlanRequest
from db.plan_supabase import save_learning_plan_to_db, get_latest_plan_by_user
from supabase import AsyncClient
import json
from typing import List, Dict
from fastapi import HTTPException

# 추천 플랜(템플릿) 정의 (수정 없음)
PREDEFINED_PLANS: Dict[str, Dict] = {
    "toeic_master": {
        "name": "TOEIC 900점 마스터",
        "description": "토익 고득점을 목표로 문법과 발음 위주로 집중 학습하는 플랜입니다.",
        "params": {
            "goal_level": 8, "frequency_type": "daily", "frequency_value": 1,
            "session_duration_minutes": 60, "preferred_styles": ["grammar", "pronunciation"]
        }
    },
    "daily_conversation": {
        "name": "매일 꾸준히 회화 연습",
        "description": "매일 짧은 시간이라도 회화 연습에 집중하여 유창성을 기르는 플랜입니다.",
        "params": {
            "goal_level": 5, "frequency_type": "daily", "frequency_value": 1,
            "session_duration_minutes": 20, "preferred_styles": ["conversation"]
        }
    },
    "balanced_growth": {
        "name": "균형 성장 플랜",
        "description": "회화, 문법, 발음 모든 영역을 골고루 학습하며 전반적인 실력을 향상시킵니다.",
        "params": {
            "goal_level": 6, "frequency_type": "interval", "frequency_value": 2,
            "session_duration_minutes": 45, "preferred_styles": ["conversation", "grammar", "pronunciation"]
        }
    }
}

# 학습 계획 계산에 사용되는 가중치 (템플릿용)
LEVEL_DIFFERENCE_WEIGHT = 10
DAILY_FREQUENCY_WEIGHT = -5
INTERVAL_FREQUENCY_WEIGHT = 5
SESSION_DURATION_WEIGHT = -0.5

def get_plan_templates() -> List[Dict[str, str]]:
    """추천 플랜 목록을 반환합니다."""
    template_list = []
    for id, plan in PREDEFINED_PLANS.items():
        template_list.append({"id": id, "name": plan["name"], "description": plan["description"]})
    return template_list

# 템플릿 기반 계획 생성 함수
def _create_detailed_learning_plan(request: LearningPlanRequest) -> dict:
    level_diff = request.goal_level - request.current_level
    estimated_days = 30 + (level_diff * LEVEL_DIFFERENCE_WEIGHT)

    if request.frequency_type == 'daily':
        estimated_days += (request.frequency_value * DAILY_FREQUENCY_WEIGHT)
        frequency_description = f"하루에 {request.frequency_value}번 학습"
    else: # 'interval'
        estimated_days += (request.frequency_value * INTERVAL_FREQUENCY_WEIGHT)
        frequency_description = f"{request.frequency_value}일에 1번 학습"

    estimated_days += (request.session_duration_minutes * SESSION_DURATION_WEIGHT)
    estimated_days = max(7, int(estimated_days))

    styles = request.preferred_styles
    num_styles = len(styles)
    total_duration = request.session_duration_minutes

    # ▼▼▼ [수정] time_distribution 구조 변경 ▼▼▼
    # 회화는 분, 문법/발음은 횟수(10분당 1회로 가정)로 변환
    time_distribution = {"conversation": 0, "grammar": 0, "pronunciation": 0}

    if num_styles > 0:
        time_per_style = total_duration / num_styles
        for style in styles:
            if style == "conversation":
                time_distribution["conversation"] = int(time_per_style)
            elif style == "grammar":
                time_distribution["grammar"] = max(1, int(time_per_style / 10)) # 10분당 1회
            elif style == "pronunciation":
                time_distribution["pronunciation"] = max(1, int(time_per_style / 10)) # 10분당 1회

    # 요약 정보 생성
    summary_lines = [
        f"총 소요 일수 : {estimated_days}일",
        f"학습 주기 : {frequency_description}"
    ]
    if time_distribution["conversation"] > 0:
        summary_lines.append(f"회화 학습 : {time_distribution['conversation']}분")
    if time_distribution["grammar"] > 0:
        summary_lines.append(f"문법 연습 : {time_distribution['grammar']}회")
    if time_distribution["pronunciation"] > 0:
        summary_lines.append(f"발음 연습 : {time_distribution['pronunciation']}회")

    plan_summary = "\n".join(summary_lines)

    internal_plan = LearningPlanInternal(
        user_id=request.user_id, user_level=request.current_level, goal_level=request.goal_level,
        estimated_days=estimated_days, frequency_description=frequency_description,
        total_session_duration=time_distribution["conversation"], # 총 학습시간은 회화 시간으로 설정
        time_distribution=time_distribution,
        plan_summary=plan_summary
    )
    return internal_plan.model_dump()


def create_plan_from_template(user_id: str, template_id: str, current_level: int) -> dict:
    """템플릿을 기반으로 학습 계획을 생성합니다."""
    template = PREDEFINED_PLANS.get(template_id)
    if not template:
        raise HTTPException(status_code=404, detail="선택한 추천 플랜을 찾을 수 없습니다.")

    plan_params = template["params"]
    full_request = LearningPlanRequest(
        user_id=user_id, current_level=current_level, goal_level=plan_params["goal_level"],
        frequency_type=plan_params["frequency_type"], frequency_value=plan_params["frequency_value"],
        session_duration_minutes=plan_params["session_duration_minutes"], preferred_styles=plan_params["preferred_styles"]
    )
    return _create_detailed_learning_plan(full_request)


# ▼▼▼ [수정] 직접 설정값으로 학습 계획을 생성하는 로직 전체 변경 ▼▼▼
def create_direct_learning_plan(user_id: str, current_level: int, request: DirectPlanRequest) -> dict:
    """사용자가 직접 설정한 값(분, 횟수)으로 학습 계획을 생성합니다."""

    # 예상 소요 일수 계산을 위한 가중치
    CONVERSATION_WEIGHT = -0.2
    GRAMMAR_WEIGHT = -1.5
    PRONUNCIATION_WEIGHT = -1.5
    LEVEL_DIFFERENCE_WEIGHT = 10

    goal_level = current_level + 2  # 직접 생성 시 목표 레벨은 현재보다 2단계 높게 설정
    level_diff = goal_level - current_level
    estimated_days = 30 + (level_diff * LEVEL_DIFFERENCE_WEIGHT)

    # 각 항목별 학습량에 따라 예상 소요 일수 조정
    estimated_days += (request.conversation_duration * CONVERSATION_WEIGHT)
    estimated_days += (request.grammar_count * GRAMMAR_WEIGHT)
    estimated_days += (request.pronunciation_count * PRONUNCIATION_WEIGHT)
    estimated_days = max(7, int(estimated_days)) # 최소 7일

    # 요약 정보 생성
    summary_lines = [
        f"총 소요 일수 : {estimated_days}일",
        "학습 주기 : 하루에 1번 학습", # 직접 생성 시 주기는 고정
    ]
    if request.conversation_duration > 0:
        summary_lines.append(f"회화 학습 : {request.conversation_duration}분")
    if request.grammar_count > 0:
        summary_lines.append(f"문법 연습 : {request.grammar_count}회")
    if request.pronunciation_count > 0:
        summary_lines.append(f"발음 연습 : {request.pronunciation_count}회")

    plan_summary = "\n".join(summary_lines)

    # DB에 저장할 데이터 모델 생성
    internal_plan = LearningPlanInternal(
        user_id=user_id,
        user_level=current_level,
        goal_level=goal_level,
        estimated_days=estimated_days,
        frequency_description="하루에 1번 학습",
        total_session_duration=request.conversation_duration, # 대표 시간은 회화 시간으로
        time_distribution={
            "conversation": request.conversation_duration,
            "grammar": request.grammar_count,
            "pronunciation": request.pronunciation_count,
        },
        plan_summary=plan_summary
    )
    return internal_plan.model_dump()


async def save_learning_plan(plan_data: dict, db: AsyncClient) -> list:
    if 'time_distribution' in plan_data and isinstance(plan_data['time_distribution'], dict):
        plan_data['time_distribution'] = json.dumps(plan_data['time_distribution'])
    return await save_learning_plan_to_db(plan_data, db)


async def get_and_process_latest_plan(user_id: str, db: AsyncClient):
    plan_data = await get_latest_plan_by_user(user_id, db)
    if plan_data and isinstance(plan_data.get('time_distribution'), str):
        try:
            plan_data['time_distribution'] = json.loads(plan_data['time_distribution'])
        except json.JSONDecodeError:
            plan_data['time_distribution'] = {}
    return plan_data