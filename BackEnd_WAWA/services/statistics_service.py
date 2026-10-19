from datetime import datetime, timezone, date
from typing import List, Optional, Tuple, Dict, Union
from models.statistics_model import LearningLog, LearningGoal, OverallStats, ProgressStats

# 누적 통계 계산
def calculate_overall_statistics(logs: List[LearningLog]) -> OverallStats:
    stats = OverallStats()
    for log in logs:
        if log.log_type == 'conversation' and log.duration is not None:
            stats.total_conversation_duration += log.duration
        elif log.log_type == 'grammar' and log.count is not None:
            stats.total_grammar_count += log.count
        elif log.log_type == 'pronunciation' and log.count is not None:
            stats.total_pronunciation_count += log.count
    return stats

# ✅ 수정: goal 파라미터 타입을 Union으로 변경하고 딕셔너리 처리 추가
def calculate_progress_statistics(
        logs: List[LearningLog],
        goal: Union[LearningGoal, Dict, None]
) -> Optional[ProgressStats]:
    if not goal:
        return None

    # ✅ 딕셔너리인 경우 LearningGoal 객체로 변환
    if isinstance(goal, dict):
        try:
            goal = LearningGoal(**goal)
        except Exception as e:
            print(f"learning_goals 파싱 오류: {e}")
            return None

    # ✅ created_at이 문자열인 경우 datetime으로 변환
    goal_created_at = goal.created_at
    if isinstance(goal_created_at, str):
        try:
            goal_created_at = datetime.fromisoformat(goal_created_at.replace('Z', '+00:00'))
        except Exception as e:
            print(f"created_at 파싱 오류: {e}")
            # 파싱 실패 시 모든 로그 포함
            goal_created_at = datetime.min

    # ✅ 로그의 created_at도 문자열일 수 있으므로 처리
    progress_logs = []
    for log in logs:
        log_created_at = log.created_at
        if isinstance(log_created_at, str):
            try:
                log_created_at = datetime.fromisoformat(log_created_at.replace('Z', '+00:00'))
            except Exception:
                continue  # 파싱 실패한 로그는 스킵

        if log_created_at >= goal_created_at:
            progress_logs.append(log)

    current_duration = 0
    current_grammar_count = 0
    current_pronunciation_count = 0

    for log in progress_logs:
        if log.log_type == 'conversation' and log.duration is not None:
            current_duration += log.duration
        elif log.log_type == 'grammar' and log.count is not None:
            current_grammar_count += log.count
        elif log.log_type == 'pronunciation' and log.count is not None:
            current_pronunciation_count += log.count

    progress = ProgressStats(
        conversation_progress=round((current_duration / goal.conversation_goal) * 100, 2) if goal.conversation_goal > 0 else 0,
        grammar_progress=round((current_grammar_count / goal.grammar_goal) * 100, 2) if goal.grammar_goal > 0 else 0,
        pronunciation_progress=round((current_pronunciation_count / goal.pronunciation_goal) * 100, 2) if goal.pronunciation_goal > 0 else 0,
    )
    return progress

def generate_daily_feedback(
        today_progress: Dict[str, int],
        learning_goals: Optional[Dict[str, int]]
) -> Optional[Dict[str, str]]:
    """오늘의 진행률과 목표를 기반으로 동적 피드백 메시지를 생성합니다."""

    # 학습 목표가 설정되지 않았으면 피드백을 생성하지 않습니다.
    if not learning_goals:
        return None

    # 목표 대비 달성률(%) 계산
    conversation_goal = learning_goals.get('conversation_goal', 0)
    grammar_goal = learning_goals.get('grammar_goal', 0)
    pronunciation_goal = learning_goals.get('pronunciation_goal', 0)

    conversation_progress = (today_progress.get('conversation', 0) / conversation_goal * 100) if conversation_goal > 0 else 0
    grammar_progress = (today_progress.get('grammar', 0) / grammar_goal * 100) if grammar_goal > 0 else 0
    pronunciation_progress = (today_progress.get('pronunciation', 0) / pronunciation_goal * 100) if pronunciation_goal > 0 else 0

    goal_count = sum(1 for goal in [conversation_goal, grammar_goal, pronunciation_goal] if goal > 0)

    # Flutter의 로직을 그대로 파이썬으로 구현
    if goal_count > 0 and conversation_progress >= 100 and grammar_progress >= 100 and pronunciation_progress >= 100:
        return {
            "message": "모든 목표를 달성하셨어요! 정말 완벽한 하루입니다! 🥳",
            "icon": "emoji_events",
            "color": "amber"
        }
    elif conversation_progress > 80 or grammar_progress > 80 or pronunciation_progress > 80:
        return {
            "message": "목표 달성이 눈앞이에요! 조금만 더 힘내세요! 🔥",
            "icon": "local_fire_department",
            "color": "deepOrange"
        }
    elif conversation_progress > 0 or grammar_progress > 0 or pronunciation_progress > 0:
        return {
            "message": "오늘도 꾸준히 학습하고 계시는군요! 정말 멋져요. 👍",
            "icon": "directions_run",
            "color": "green"
        }
    else:
        return {
            "message": "오늘의 학습을 시작하고 목표를 달성해보세요! 🚀",
            "icon": "rocket_launch",
            "color": "blue"
        }

def generate_learning_progress(
        logs: List[LearningLog],
        goal_data: Dict
) -> Dict:
    """
    학습 목표와 로그를 기반으로 진척도 데이터와 피드백을 생성합니다. (시간대 처리 강화)
    """
    try:
        goal = LearningGoal(**goal_data)
        # goal.created_at은 Pydantic 모델에 의해 datetime 객체로 변환된 상태
    except Exception as e:
        print(f"오류: 학습 목표 데이터를 파싱할 수 없습니다. 에러: {e}")
        return None

    # 1. 목표 시간을 시간대 정보가 있는(aware) UTC 시간으로 통일합니다.
    goal_time = goal.created_at
    if goal_time.tzinfo is None:
        goal_time = goal_time.replace(tzinfo=timezone.utc) # naive하면 UTC로 간주

    print(f"DEBUG: 목표 설정 시간 (UTC): {goal_time}")

    # 2. 목표 시간 이후의 로그만 필터링합니다.
    progress_logs = []
    for log in logs:
        # log.created_at은 DB에서 온 문자열 상태
        if not log.created_at or not isinstance(log.created_at, str):
            continue

        try:
            # 로그 시간(문자열)을 aware datetime 객체로 변환
            log_time = datetime.fromisoformat(log.created_at.replace('Z', '+00:00'))

            # 만약 시간대 정보가 없다면 UTC로 간주하여 통일
            if log_time.tzinfo is None:
                log_time = log_time.replace(tzinfo=timezone.utc)

            # 이제 두 aware datetime 객체를 안전하게 비교합니다.
            if log_time >= goal_time:
                progress_logs.append(log)
            # else:
            #     print(f"DEBUG: 로그 건너뜀 (기록 시간: {log_time} < 목표 시간: {goal_time})")

        except ValueError:
            print(f"DEBUG: 잘못된 타임스탬프 형식으로 로그를 건너뜁니다: {log.created_at}")
            continue

    print(f"DEBUG: 목표 설정 이후 {len(progress_logs)}개의 학습 로그를 찾았습니다.")

    # 3. 이하 로직은 이전과 동일하게 집계, 계산, 피드백 생성을 수행합니다.
    achieved_conversation = sum(log.duration for log in progress_logs if log.log_type == 'conversation' and log.duration)
    achieved_grammar = sum(log.count for log in progress_logs if log.log_type == 'grammar' and log.count)
    achieved_pronunciation = sum(log.count for log in progress_logs if log.log_type == 'pronunciation' and log.count)

    def calculate_rate(achieved, goal_value):
        if not goal_value or goal_value == 0:
            return 0.0
        return min(achieved / goal_value, 1.0)

    conv_rate = calculate_rate(achieved_conversation, goal.conversation_goal)
    gram_rate = calculate_rate(achieved_grammar, goal.grammar_goal)
    pron_rate = calculate_rate(achieved_pronunciation, goal.pronunciation_goal)

    active_rates = [rate for rate, goal_val in [(conv_rate, goal.conversation_goal), (gram_rate, goal.grammar_goal), (pron_rate, goal.pronunciation_goal)] if goal_val > 0]
    overall_progress = sum(active_rates) / len(active_rates) if active_rates else 0.0

    feedback = "학습을 시작하여 목표를 향해 나아가 보세요!"
    active_progress_map = {}
    if goal.conversation_goal > 0: active_progress_map["회화"] = conv_rate
    if goal.grammar_goal > 0: active_progress_map["문법"] = gram_rate
    if goal.pronunciation_goal > 0: active_progress_map["발음"] = pron_rate

    if active_progress_map:
        if overall_progress >= 1.0:
            feedback = "대단해요! 모든 목표를 달성했습니다. 새로운 목표를 설정해 더 높은 곳으로 나아가세요."
        elif overall_progress > 0.1:
            min_progress_area = min(active_progress_map, key=active_progress_map.get)
            max_progress_area = max(active_progress_map, key=active_progress_map.get)
            feedback = f"전체적으로 순조롭게 진행 중입니다. 특히 '{max_progress_area}' 분야에서 잘하고 계세요. '{min_progress_area}' 학습에 조금 더 집중하면 더 좋은 결과를 얻을 수 있을 거예요."

    return {
        "overall_progress": overall_progress,
        "conversation": {"goal": goal.conversation_goal, "achieved": achieved_conversation, "progress": conv_rate},
        "grammar": {"goal": goal.grammar_goal, "achieved": achieved_grammar, "progress": gram_rate},
        "pronunciation": {"goal": goal.pronunciation_goal, "achieved": achieved_pronunciation, "progress": pron_rate},
        "feedback": feedback
    }

def generate_overall_feedback(stats: OverallStats) -> str:
    """
    누적 학습 통계(OverallStats)를 기반으로 종합적인 피드백을 생성합니다.
    """
    total_duration = stats.total_conversation_duration
    total_grammar = stats.total_grammar_count
    total_pronunciation = stats.total_pronunciation_count

    total_activities = total_duration + total_grammar + total_pronunciation

    if total_activities == 0:
        return "아직 기록된 학습이 없네요. 오늘부터 꾸준히 학습 기록을 쌓아나가 보세요!"

    feedback_parts = []

    # 가장 많이 한 학습 활동 찾기
    activities = {
        "회화": total_duration,
        "문법": total_grammar,
        "발음": total_pronunciation
    }
    if max(activities.values()) > 0:
        main_activity = max(activities, key=activities.get)
        feedback_parts.append(f"지금까지 '{main_activity}' 학습에 가장 많은 시간을 투자하셨군요! 정말 꾸준하고 멋져요.")

    # 부족한 학습 활동 찾기
    min_activities = [name for name, value in activities.items() if value == 0]
    if len(min_activities) > 0:
        missing_parts = ', '.join(min_activities)
        feedback_parts.append(f"앞으로 '{missing_parts}' 연습도 함께 진행하시면 더욱 균형 잡힌 실력 향상을 기대할 수 있을 거예요.")

    if total_duration > 1000:
        feedback_parts.append("총 회화 시간이 1000분을 돌파했습니다! 유창한 스피킹 실력이 눈앞에 보여요.")

    return " ".join(feedback_parts)

def generate_today_progress_with_feedback(
        logs: List[LearningLog],
        goal_data: Dict
) -> Dict:
    """
    오늘 날짜의 로그와 학습 목표를 기반으로 상세 진척도 데이터와 피드백을 생성합니다.
    """
    try:
        goal = LearningGoal(**goal_data)
    except Exception as e:
        print(f"오류: 학습 목표 데이터를 파싱할 수 없습니다. 에러: {e}")
        return None

    # 1. 오늘 날짜의 로그만 필터링합니다.
    today_str = date.today().isoformat()
    today_logs = [log for log in logs if log.created_at and log.created_at.startswith(today_str)]

    # 2. 이하 로직은 generate_learning_progress와 거의 동일합니다.
    achieved_conversation = sum(log.duration for log in today_logs if log.log_type == 'conversation' and log.duration)
    achieved_grammar = sum(log.count for log in today_logs if log.log_type == 'grammar' and log.count)
    achieved_pronunciation = sum(log.count for log in today_logs if log.log_type == 'pronunciation' and log.count)

    def calculate_rate(achieved, goal_value):
        if not goal_value or goal_value == 0:
            return 0.0
        return min(achieved / goal_value, 1.0)

    conv_rate = calculate_rate(achieved_conversation, goal.conversation_goal)
    gram_rate = calculate_rate(achieved_grammar, goal.grammar_goal)
    pron_rate = calculate_rate(achieved_pronunciation, goal.pronunciation_goal)

    active_rates = [rate for rate, goal_val in [(conv_rate, goal.conversation_goal), (gram_rate, goal.grammar_goal), (pron_rate, goal.pronunciation_goal)] if goal_val > 0]
    overall_progress = sum(active_rates) / len(active_rates) if active_rates else 0.0

    feedback = "오늘의 학습을 시작하여 목표를 달성해보세요!"
    if overall_progress >= 1.0:
        feedback = "대단해요! 오늘의 모든 목표를 달성했습니다! 🎉"
    elif overall_progress > 0:
        feedback = "목표를 향해 순조롭게 나아가고 있어요. 조금만 더 힘내세요!"

    return {
        "overall_progress": overall_progress,
        "conversation": {"goal": goal.conversation_goal, "achieved": achieved_conversation, "progress": conv_rate},
        "grammar": {"goal": goal.grammar_goal, "achieved": achieved_grammar, "progress": gram_rate},
        "pronunciation": {"goal": goal.pronunciation_goal, "achieved": achieved_pronunciation, "progress": pron_rate},
        "feedback": feedback
    }