import sys
import os
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context

# --- .env 파일 로드 설정 ---
# Alembic이 .env 파일의 환경변수(DATABASE_URL)를 인식할 수 있도록
# 스크립트 최상단에서 dotenv를 로드합니다.
from dotenv import load_dotenv
load_dotenv()
# --- .env 파일 로드 설정 끝 ---
from models import Base


# --- 애플리케이션 모델 경로 설정 ---
# 현재 스크립트(env.py)의 위치를 기준으로 프로젝트 루트 경로를 시스템 경로에 추가합니다.
# 이렇게 해야 alembic 폴더 밖의 database.models 모듈을 임포트할 수 있습니다.
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
# --- 애플리케이션 모델 경로 설정 끝 ---


# Alembic Config 객체로, alembic.ini 파일의 값에 접근할 수 있습니다.
config = context.config

# 파이썬 로깅을 설정합니다.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# --- 타겟 메타데이터 설정 ---
# Alembic이 데이터베이스 스키마를 비교할 기준으로 사용할 SQLAlchemy 모델의 메타데이터를 지정합니다.
# 우리 프로젝트의 모든 SQLAlchemy 모델이 상속받는 Base 객체의 metadata를 가져옵니다.

target_metadata = Base.metadata
# --- 타겟 메타데이터 설정 끝 ---


def run_migrations_offline() -> None:
    """'오프라인' 모드(DB에 직접 연결하지 않고 SQL 스크립트만 생성)로 마이그레이션을 실행합니다."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """'온라인' 모드(DB에 직접 연결)로 마이그레이션을 실행합니다."""
    # alembic.ini 파일의 설정과 .env의 DATABASE_URL을 바탕으로 데이터베이스 엔진을 생성합니다.
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection, target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


# 현재 실행 모드(온라인/오프라인)에 따라 적절한 함수를 호출합니다.
if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()