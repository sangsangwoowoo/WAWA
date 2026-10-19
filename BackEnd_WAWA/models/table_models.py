# 데이터베이스 테이블 구조를 SQLAlchemy ORM 모델 클래스로 정의하는 파일
from sqlalchemy import (
    Column, Integer, String, Boolean, Text,
    Date, DateTime, ForeignKey, UniqueConstraint
)
from datetime import datetime, date
from sqlalchemy.orm import relationship, declarative_base

# 모든 ORM 모델이 상속받을 기본 클래스를 생성합니다.
Base = declarative_base()

# ======================
# ✅ 사용자(User)
# ======================
class User(Base):
    __tablename__ = "user_account" # 데이터베이스 테이블 이름

    id = Column(Integer, primary_key=True, index=True) # 기본 키
    username = Column(String, unique=True, index=True, nullable=False) # 사용자 이름 (고유값)
    password = Column(String, nullable=False) # 비밀번호
    is_admin = Column(Boolean, default=False) # 관리자 여부
    is_active = Column(Boolean, default=True)  # 논리적 삭제(soft delete)를 위한 활성화 플래그

    native_language = Column(String, nullable=True) # 모국어
    learning_language = Column(String, nullable=True) # 학습 언어
    level = Column(String, default="beginner") # 레벨 (초기값 'beginner')

    # 관계 설정: User 모델과 다른 모델 간의 연결을 정의합니다.
    # 'back_populates'는 양방향 관계를 설정하여 양쪽 모델에서 서로 접근할 수 있게 합니다.
    level_test_results = relationship("LevelTestResult", back_populates="user")
    attendances = relationship("Attendance", back_populates="user")

# ======================
# ✅ 공지사항(Notice)
# ======================
class Notice(Base):
    __tablename__ = "notices"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200), nullable=False)
    content = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

# ======================
# ✅ FAQ
# ======================
class FAQ(Base):
    __tablename__ = "faqs"

    id = Column(Integer, primary_key=True, index=True)
    question = Column(String(300), nullable=False)
    answer = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

# ======================
# ✅ 레벨 테스트 문제(LevelTestQuestion)
# ======================
class LevelTestQuestion(Base):
    __tablename__ = "level_test_questions"

    id = Column(Integer, primary_key=True, index=True)
    question_text = Column(String, nullable=False)
    correct_answer = Column(String, nullable=False)
    difficulty = Column(Integer, nullable=False)  # 1=초급, 2=중급, 3=고급

# ======================
# ✅ 레벨 테스트 결과(LevelTestResult)
# ======================
class LevelTestResult(Base):
    __tablename__ = "level_test_results"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    score = Column(Integer, nullable=False)
    level = Column(String, nullable=False)  # beginner / intermediate / advanced

    # ✅ User와 연결
    user = relationship("User", back_populates="level_test_results")

# ======================
# ✅ 출석체크(Attendance)
# ======================
class Attendance(Base):
    __tablename__ = "attendances"

    id = Column(Integer, primary_key=True, index=True)
    # 외래 키: users 테이블의 id를 참조합니다.
    # 'ondelete="CASCADE"'는 참조하는 User가 삭제될 때 관련된 Attendance 기록도 함께 삭제되도록 합니다.
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    date = Column(Date, default=date.today) # 출석 날짜
    created_at = Column(DateTime, default=datetime.utcnow) # 생성 시각

    # 복합 유니크 제약조건: 한 명의 유저(user_id)가 같은 날짜(date)에 중복으로 출석할 수 없도록 합니다.
    __table_args__ = (UniqueConstraint("user_id", "date", name="_user_date_uc"),)

    # User 모델과의 양방향 관계 설정
    user = relationship("User", back_populates="attendances")
