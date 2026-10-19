import os
import asyncio
from dotenv import load_dotenv
from supabase import create_client, Client
from datetime import datetime

# .env 파일에서 Supabase 접속 정보를 불러옵니다.
load_dotenv()

async def insert_notices():
    """공지사항 데이터를 Supabase 테이블에 삽입하는 스크립트"""

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

    # --- 데이터베이스에 추가할 공지사항 목록 ---
    # id와 created_at은 자동으로 생성되므로 title과 content만 제공합니다.
    notice_list = [
        {
            "title": "AI 언어 학습 앱에 오신 것을 환영합니다!",
            "content": "안녕하세요, 학습자님! AI 언어 학습 앱과 함께 새로운 언어의 세계를 탐험할 준비가 되셨나요?\n\n저희 앱은 최신 AI 기술을 활용하여 여러분의 발음을 정교하게 분석하고, 실제 원어민과 대화하는 듯한 경험을 제공합니다. 꾸준히 학습하여 유창한 언어 실력을 만들어보세요!\n\n궁금한 점은 언제든지 '설정 > 자주 찾는 질문' 또는 '피드백 작성' 메뉴를 이용해주세요."
        },
        {
            "title": "[업데이트] 발음 분석 엔진이 더 똑똑해졌어요!",
            "content": "더욱 정교한 발음 교정을 위해 AI 분석 엔진이 v2.0으로 업그레이드되었습니다.\n\n[주요 개선 사항]\n- **억양 및 리듬 분석 강화:** 이제 문장의 전체적인 억양 곡선과 리듬의 자연스러움을 더욱 세밀하게 분석합니다.\n- **상세 피드백 제공:** 단순히 점수만 알려주는 것을 넘어, 어떤 단어의 강세가 틀렸는지, 말의 속도는 어땠는지 등 구체적인 피드백을 제공합니다.\n\n지금 바로 '학습' 탭에서 새로워진 분석 엔진의 성능을 경험해보세요!"
        },
        {
            "title": "함께 공부해요! '커뮤니티' 기능 오픈 안내",
            "content": "혼자 하는 공부가 지겨우셨나요? 이제 다른 학습자들과 함께 소통하며 학습 동기를 얻을 수 있는 '커뮤니티' 기능이 오픈되었습니다!\n\n- **자유게시판:** 학습 꿀팁이나 일상 이야기를 자유롭게 나눠보세요.\n- **질문게시판:** 공부하다 막히는 부분이 있다면 언제든지 질문하세요.\n- **스터디모집:** 비슷한 목표를 가진 스터디 파트너를 찾아보세요.\n\n지금 바로 '커뮤니티' 탭에서 첫 글을 작성해보세요!"
        },
        {
            "title": "[꿀팁] '다른 문장' 버튼으로 새로운 표현을 만나보세요!",
            "content": "발음 연습이 지루하지 않도록, 저희 앱은 수만 개의 문장 데이터베이스를 갖추고 있습니다.\n\n'학습' 탭에서 **'다른 문장'** 버튼을 누를 때마다 일상 회화, 비즈니스, 여행 등 다양한 상황에서 사용되는 새로운 문장으로 연습할 수 있습니다. 매일 새로운 문장에 도전하며 표현의 폭을 넓혀보세요!"
        },
        {
            "title": "[이벤트 예고] 꾸준함이 실력! 첫 출석 체크 챌린지",
            "content": "매일매일 꾸준히 학습하는 습관을 기를 수 있도록, 곧 '출석 체크 챌린지' 이벤트가 시작될 예정입니다.\n\n7일, 14일, 30일 연속 출석을 달성하시는 분들께는 특별한 캐릭터 아이템과 학습 포인트를 드릴 예정이니 많은 참여 바랍니다. 자세한 내용은 다음 주 공지를 확인해주세요!"
        }
    ]

    print(f"\n총 {len(notice_list)}개의 공지사항을 데이터베이스에 추가합니다...")

    try:
        # Supabase의 'notices' 테이블에 데이터 목록을 한 번에 삽입합니다.
        data, count = supabase.table('notices').insert(notice_list).execute()

        if data and len(data[1]) > 0:
            print(f"✅ 성공! {len(data[1])}개의 공지사항이 데이터베이스에 성공적으로 추가되었습니다.")
        else:
            print(f"⚠️ 데이터 삽입은 성공했으나, 반환된 데이터가 없습니다. DB를 확인해주세요.")

    except Exception as e:
        print(f"❌ 데이터베이스 삽입 중 오류 발생: {e}")
        print("   'notices' 테이블 이름과 컬럼('title', 'content')이 정확한지 확인해주세요.")


if __name__ == "__main__":
    # 비동기 함수를 실행합니다.
    asyncio.run(insert_notices())