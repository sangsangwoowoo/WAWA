import os
import asyncio
from dotenv import load_dotenv
from supabase import create_client, Client

# .env 파일에서 Supabase 접속 정보를 불러옵니다.
load_dotenv()

async def insert_faqs():
    """FAQ 데이터를 Supabase 테이블에 삽입하는 스크립트"""

    # --- Supabase 클라이언트 초기화 ---
    url: str = os.environ.get("SUPABASE_URL")
    key: str = os.environ.get("SUPABASE_KEY")

    if not url or not key:
        print("❌ 오류: .env 파일에 SUPABASE_URL과 SUPABASE_KEY를 설정해주세요.")
        return

    try:
        supabase: Client = create_client(url, key)
        print("✅ Supabase 클라이언트 초기화 성공!")
    except Exception as e:
        print(f"❌ Supabase 클라이언트 초기화 실패: {e}")
        return

    # --- 데이터베이스에 추가할 FAQ 목록 ---
    faq_list = [
        {
            "question": "처음 로그인했는데, 왜 바로 학습을 시작할 수 없나요?",
            "answer": "저희 앱은 사용자에게 꼭 맞는 학습 경험을 제공하기 위해, 첫 로그인 시에만 초기 설정(Onboarding) 과정을 진행합니다. 간단한 레벨 테스트를 통해 현재 실력을 파악하고, 학습 목표와 함께 공부할 캐릭터를 선택하는 과정입니다. 이 과정을 완료하면 다음 로그인부터는 바로 메인 홈 화면으로 이동합니다."
        },
        {
            "question": "발음 연습 문장이 매번 바뀌나요? 어디서 가져오는 건가요?",
            "answer": "네, 맞습니다. 지루하지 않은 학습을 위해 앱에는 수만 개의 실제 원어민 문장 데이터가 내장되어 있습니다. '다른 문장' 버튼을 누를 때마다 이 중에서 새로운 문장을 랜덤으로 보여주어, 매번 새로운 내용으로 연습할 수 있습니다."
        },
        {
            "question": "'상황별 회화'의 AI는 실제 사람처럼 대화하나요?",
            "answer": "네. 저희의 AI는 실제 원어민처럼 생각하고 답변하도록 훈련되었습니다. 공항, 식당 등 다양한 상황에서 사용자의 답변을 이해하고, 실제 사람과 대화하는 것처럼 자연스럽게 대화를 이어나가며 실전 회화 능력을 키울 수 있도록 돕습니다."
        },
        {
            "question": "커뮤니티에서는 무엇을 할 수 있나요?",
            "answer": "커뮤니티는 다른 학습자들과 교류할 수 있는 공간입니다. 궁금한 것을 질문하는 '질문게시판', 유용한 정보를 공유하는 '정보공유', 함께 공부할 스터디 그룹을 찾는 '스터디모집' 등 다양한 활동을 통해 학습 동기를 얻고 정보를 나눌 수 있습니다."
        },
        {
            "question": "발음 점수는 어떤 기준으로 채점되나요?",
            "answer": "발음 평가는 크게 3가지 기준으로 이루어집니다.\n1. 정확도 (Accuracy): 단어 하나하나를 얼마나 정확하게 발음했는지 평가합니다.\n2. 유창성 (Fluency): 망설임이나 불필요한 끊김 없이 얼마나 부드럽게 문장을 말했는지 평가합니다.\n3. 운율 (Prosody): 원어민처럼 자연스러운 억양, 리듬, 강세를 사용했는지 종합적으로 평가합니다."
        },
        {
            "question": "레벨 테스트를 다시 볼 수 있나요?",
            "answer": "현재 버전에서는 최초 가입 시에만 레벨 테스트를 제공하고 있습니다. 한번 결정된 레벨은 '내 정보 > 프로필 관리'에서 확인할 수 있으며, 꾸준한 학습을 통해 실력이 향상되면 다음 레벨로 올라갈 수 있습니다. 추후 정기적으로 실력을 재측정하는 기능이 추가될 예정입니다."
        },
        {
            "question": "제 목소리는 어떻게 사용되고 저장되나요?",
            "answer": "사용자가 '학습' 탭에서 처음 녹음한 목소리는, 사용자만을 위한 개인화된 'AI 튜터' 목소리를 만드는 데 단 한 번 사용됩니다. 이 목소리는 안전하게 저장되며, 오직 사용자 본인에게 '교정 발음'을 들려주는 기능에만 사용됩니다. 다른 목적으로 사용되거나 타인에게 공개되지 않습니다."
        },
        {
            "question": "출석 체크는 어떻게 하며, 혜택이 있나요?",
            "answer": "홈 화면의 '출석 체크' 영역을 터치하여 출석 페이지로 이동한 뒤, '출석하기' 버튼을 누르면 완료됩니다. 꾸준히 출석하면 연속 출석 기록이 쌓이며, 추후 다양한 학습 보상(리워드)을 받을 수 있는 이벤트에 참여할 수 있는 자격이 주어집니다."
        }
    ]

    print(f"\n총 {len(faq_list)}개의 FAQ를 데이터베이스에 추가합니다...")

    try:
        # Supabase의 'faqs' 테이블에 데이터 목록을 한 번에 삽입합니다.
        # .insert()에 리스트를 전달하면 됩니다.
        data, count = supabase.table('faqs').insert(faq_list).execute()

        # 성공적으로 삽입되었는지 확인 (에러가 없으면 성공)
        if data and len(data[1]) == len(faq_list):
            print(f"✅ 성공! {len(data[1])}개의 FAQ가 데이터베이스에 성공적으로 추가되었습니다.")
        else:
            # PostgREST v10 이상은 count를 반환하지 않을 수 있으므로 data[1]의 길이로 확인
            print("⚠️ 일부 데이터만 삽입되었거나 응답 형식이 다를 수 있습니다. DB를 확인해주세요.")

    except Exception as e:
        print(f"❌ 데이터베이스 삽입 중 오류 발생: {e}")
        print("   'faqs' 테이블 이름과 컬럼('question', 'answer')이 정확한지 확인해주세요.")


if __name__ == "__main__":
    # 비동기 함수를 실행합니다.
    asyncio.run(insert_faqs())