from dotenv import load_dotenv
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from api import point_api, plan_api, statistics_api, grammar_api, login_api, challenge_api, vocabulary_api, pronunciation_api, \
    study_group_api, admin_api, community_api, notification_api, attendance_api, faq_api, leveltest_api, notice_api, \
    user_api
from services.performance_monitor import performance_monitor

# .env 파일에서 환경 변수 로드
load_dotenv()

# FastAPI 앱 초기화
app = FastAPI(
    title="통합 모듈 API",
    description="로그인, 사용자별 맞춤 학습 계획 생성, 학습 통계 조회 API",
    version="1.0.0"
)

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    print(f"=== Validation Error ===")
    print(f"Body: {await request.body()}")
    print(f"Errors: {exc.errors()}")
    print(f"======================")
    return JSONResponse(
        status_code=422,
        content={"detail": exc.errors(), "body": str(await request.body())}
    )

# --- API 라우터 ---

# 16. 포인트 api
app.include_router(
    point_api.router,
    prefix="/api/points",
    tags=["Points"]
)

# 15. 문법 연습 이력 API
app.include_router(
    grammar_api.router,
    prefix="/api/grammar",
    tags=["Grammar"]
)

# 1. 학습 계획 성생 API
app.include_router(
    plan_api.router,
    prefix="/api/plans",
    tags=["Learning Plans"]
)
# 2. 학습 통계 조회 API
app.include_router(
    statistics_api.router,
    prefix="/api/statistics",
    tags=["Learning Statistics"]
)

# 3. 로그인 API
app.include_router(
    login_api.router,
    prefix="/auth",
    tags=["Auth"]
)

# 4. 사용자 프로필 API
app.include_router(
    user_api.router,
    prefix="/api/user",
    tags=["User"]
)

# 5. 관리자 API
app.include_router(
    admin_api.router,
    prefix="/api/admin",
    tags=["Admin"]
)

# 6. 공지사항 API
app.include_router(
    notice_api.router,
    prefix="/api/notices",
    tags=["Notices"]
)

# 7. FAQ API
app.include_router(
    faq_api.router,
    prefix="/api/faqs",
    tags=["FAQs"]
)

# 8. 레벨 테스트 API
app.include_router(
    leveltest_api.router,
    prefix="/api/level-test",
    tags=["Level Test"]
)

# 9. 출석 체크 API
app.include_router(
    attendance_api.router,
    prefix="/api/attendance",
    tags=["Attendance"]
)

# 10. 푸시 알림 API
app.include_router(
    notification_api.router,
    prefix="/api/notifications",
    tags=["User Notifications"]
)

# 11. 커뮤니티 API
app.include_router(
    community_api.router,
    prefix="/api/community",
    tags=["Community"]
)

# 12. 학습 그룹
app.include_router(
    study_group_api.router,
    prefix="/api/study-groups",
    tags=["Study Groups"]
)

# 13. 발음 분석 내역
app.include_router(
    pronunciation_api.router,
    prefix="/api/pronunciation",
    tags=["Pronunciation"]
)

# 14. 단어장 API
app.include_router(
    vocabulary_api.router,
    prefix="/api/vocabulary",
    tags=["Vocabulary"]
)

# 16. 학습 그룹 내 챌린지
app.include_router(
    challenge_api.router,
    prefix="/api/challenges",
    tags=["Challenges"]
)

# 서버 정상 동작 확인
@app.get("/", tags=["Root"])
async def read_root():
    return {"message": "서버 정상 동작중"}

@app.on_event("shutdown")
def shutdown_event():
    print("👋 서버가 종료됩니다. 성능 리포트를 생성합니다...")
    performance_monitor.generate_report()