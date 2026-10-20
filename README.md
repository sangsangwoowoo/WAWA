# WAWA

WAWA는 AI 기반 음성 분석, 실전 회화 연습, 학습 관리 기능을 결합한 언어 학습 플랫폼입니다.

이 저장소는 다음 3개의 구성 요소로 나뉩니다.

- AI_WAWA: 음성 인식, 발음 평가, 대화 AI, 레벨 테스트, 데이터 수집/파인튜닝 관련 Python FastAPI 서버
- BackEnd_WAWA: 사용자 인증, 학습 계획, 통계, 커뮤니티, 관리자 기능을 담당하는 FastAPI 백엔드
- Front_WAWA: Flutter 기반 모바일/웹 클라이언트

## 프로젝트 개요

WAWA는 사용자가 실제 생활 상황에서 영어/한국어/일본어/중국어 등 여러 언어를 연습할 수 있도록 돕는 서비스입니다. 주요 기능은 다음과 같습니다.

- 실시간 대화형 AI 튜터
- 발음 및 억양 분석
- 음성 입력 기반 STT/TTS 기능
- 학습 레벨 진단 및 맞춤 학습 계획
- 출석, 포인트, 커뮤니티, 스터디 그룹, 공지/FAQ 기능
- Supabase 기반 데이터 저장 및 인증

## 폴더 구조

```text
WAWA/
├── AI_WAWA/              # AI 서버 및 데이터 파이프라인
│   ├── app/
│   ├── tests/
│   ├── training_data/
│   ├── requirements.txt
│   └── build.sh
├── BackEnd_WAWA/         # API 서버
│   ├── api/
│   ├── core/
│   ├── db/
│   ├── models/
│   ├── services/
│   ├── requirements.txt
│   ├── main.py
│   └── build.sh
├── Front_WAWA/           # Flutter 앱
│   ├── lib/
│   ├── assets/
│   ├── android/
│   ├── ios/
│   ├── pubspec.yaml
│   └── README.md
├── README.md             # 프로젝트 루트 문서
└── .gitignore
```

## 기술 스택

### AI 서버 (AI_WAWA)
- Python 3.10+
- FastAPI
- OpenAI API
- SpeechRecognition
- pyttsx3
- librosa / scipy / parselmouth
- Supabase
- Pandas / scikit-learn

### 백엔드 서버 (BackEnd_WAWA)
- Python
- FastAPI
- SQLAlchemy
- Alembic
- Supabase / PostgreSQL
- JWT 기반 인증
- FastAPI Scheduler, Push Notification 구성 요소 포함

### 프론트엔드 (Front_WAWA)
- Flutter
- Dart
- Provider / SharedPreferences
- HTTP / audio / local storage 기반 모바일 UI

## 실행 전 준비

### 1) 환경 요구사항
- Python 3.10 이상
- Flutter SDK
- Git
- Supabase 프로젝트 및 관련 키
- OpenAI API 키 (AI 대화/모델 기능 사용 시)

### 2) 환경 변수 설정
각 서버 루트에 `.env` 파일을 생성하고 아래와 같은 항목을 설정하세요.

예시:

```env
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_KEY=your-supabase-anon-key
OPENAI_API_KEY=your-openai-api-key
```

AI_WAWA와 BackEnd_WAWA 모두 환경 변수를 통해 외부 서비스 연결을 사용하므로, `.env` 파일이 반드시 있어야 합니다.

## 실행 방법

### 1) AI 서버 실행

```bash
cd AI_WAWA
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

기본 Swagger 문서는 다음 주소에서 확인할 수 있습니다.

- http://localhost:8000/docs

### 2) 백엔드 서버 실행

```bash
cd BackEnd_WAWA
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8001 --reload
```

API 문서는 다음에서 확인할 수 있습니다.

- http://localhost:8001/docs

### 3) Flutter 앱 실행

```bash
cd Front_WAWA
flutter pub get
flutter run
```

필요한 경우 플랫폼별 시뮬레이터/디바이스를 연결한 뒤 실행하면 됩니다.

## 주요 기능

### AI_WAWA
- 대화형 언어 학습 대화 생성
- 실시간 음성 입력 및 텍스트 변환
- 발음 점수/평가
- 사용자별 학습 데이터 수집
- 상황별 학습 시나리오(예: airport, restaurant, hotel, street)
- 모델 개선 및 fine-tuning 가능 구조

### BackEnd_WAWA
- 로그인/회원 정보 관리
- 사용자별 맞춤 학습 계획
- 학습 통계 / 점수 분석
- 관리자 기능
- 출석, 포인트, 공지, FAQ, 커뮤니티, 스터디 그룹 기능
- 레벨 테스트 및 학습 진행 관리

### Front_WAWA
- 사용자 로그인 및 세션 관리
- 학습 화면, 대화 연습, 퀴즈/레벨테스트 UI
- 음성 재생 및 TTS 연동
- 일정/캘린더/커뮤니티 기반 학습 관리

## 개발 참고

- AI 서버와 백엔드 서버는 별도 FastAPI 앱으로 분리되어 있어 로컬 개발 시 각각 독립적으로 실행하는 것이 편합니다.
- 프론트엔드는 백엔드 API 주소를 설정하여 실제 운영 환경에 맞게 연결해야 합니다.
- 프로젝트 구조는 학습/훈련 데이터를 기반으로 실전형 대화 연습을 중심으로 설계되어 있습니다.

## 라이선스

이 프로젝트는 별도의 명시적 라이선스가 없으면 기본적으로 내부 개발/교육 용도로 사용되는 것으로 간주합니다. 배포 또는 상업적 사용 전에 라이선스 조건을 확인해 주세요.

## 문의 및 협업

프로젝트에 대한 기획, 기능 추가, 운영 환경 구성, 배포 관련 문의는 저장소 관리자 또는 팀 내 담당자에게 문의해 주세요.
