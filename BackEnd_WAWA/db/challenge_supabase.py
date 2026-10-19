# db/challenge_supabase.py

import base64
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional

from supabase import AsyncClient


async def create_challenge(db: AsyncClient, group_id: int, user_id: str, challenge_data: Dict[str, Any]) -> Dict[str, Any]:
    """group_challenges 테이블에 새로운 챌린지 생성"""
    end_date = datetime.now() + timedelta(days=challenge_data['duration_days'])

    response = await db.table('group_challenges').insert({
        'group_id': group_id,
        'created_by_user_id': user_id,
        'title': challenge_data['title'],
        'description': challenge_data['description'],
        'challenge_type': challenge_data['challenge_type'],
        'target_value': challenge_data['target_value'],
        'end_date': end_date.isoformat(),
    }).execute()

    return response.data[0]

async def get_challenges_by_group_id(db: AsyncClient, group_id: int) -> List[Dict[str, Any]]:
    """특정 그룹의 모든 챌린지와 그룹 전체 진행률 조회"""
    # 1. 그룹의 모든 챌린지 조회
    challenges_res = await db.table('group_challenges').select('*').eq('group_id', group_id).order('end_date', desc=True).execute()
    if not challenges_res.data:
        return []

    # 2. 각 챌린지별로 전체 진행 상황 합산
    challenges_with_progress = []
    for challenge in challenges_res.data:
        progress_res = await db.table('user_challenge_progress').select('current_value').eq('challenge_id', challenge['id']).execute()

        group_current_value = sum(item['current_value'] for item in progress_res.data)

        challenge['group_current_value'] = group_current_value
        challenges_with_progress.append(challenge)

    return challenges_with_progress

async def get_challenge_details(db: AsyncClient, challenge_id: int) -> Dict[str, Any]:
    """챌린지 상세 정보와 멤버별 리더보드 조회"""
    # 1. 챌린지 기본 정보 조회
    challenge_res = await db.table('group_challenges').select('*').eq('id', challenge_id).single().execute()
    if not challenge_res.data:
        return None
    challenge_info = challenge_res.data

    # 2. 리더보드 데이터 조회 (user_challenge_progress와 user_account 테이블 JOIN)
    leaderboard_res = await db.table('user_challenge_progress') \
        .select('*, user_account:user_id(name)') \
        .eq('challenge_id', challenge_id) \
        .order('current_value', desc=True) \
        .execute()

    challenge_info['leaderboard'] = leaderboard_res.data
    return challenge_info

async def log_progress(db: AsyncClient, user_id: str, log_type: str, value: int):
    """사용자의 학습 활동을 연관된 모든 활성 챌린지에 기록"""
    # 1. 사용자가 참여 중인 그룹 목록 조회
    member_res = await db.table('group_members').select('group_id').eq('user_id', user_id).execute()
    if not member_res.data:
        return # 참여 중인 그룹이 없으면 종료

    group_ids = [item['group_id'] for item in member_res.data]

    # 2. 해당 그룹들의 활성 챌린지 중 log_type이 일치하는 것들 조회
    active_challenges = await db.table('group_challenges') \
        .select('id') \
        .in_('group_id', group_ids) \
        .eq('challenge_type', log_type) \
        .eq('is_active', True) \
        .gt('end_date', datetime.now().isoformat()) \
        .execute()

    if not active_challenges.data:
        return # 기록할 챌린지가 없으면 종료

    # 3. 각 챌린지에 대해 진행률 업데이트 또는 생성
    for challenge in active_challenges.data:
        challenge_id = challenge['id']

        # Supabase Edge Function (RPC)을 사용하여 원자적(atomic)으로 업데이트하는 것이 가장 이상적입니다.
        # 예: supabase.rpc('increment_challenge_progress', {'challenge_id': c_id, 'user_id': u_id, 'increment_value': val})
        # 여기서는 간단하게 select 후 update로 구현합니다.

        progress_res = await db.table('user_challenge_progress').select('id, current_value').eq('challenge_id', challenge_id).eq('user_id', user_id).maybe_single().execute()

        if progress_res.data:
            # 기존 기록이 있으면 업데이트
            new_value = progress_res.data['current_value'] + value
            await db.table('user_challenge_progress').update({'current_value': new_value}).eq('id', progress_res.data['id']).execute()
        else:
            # 기존 기록이 없으면 생성
            await db.table('user_challenge_progress').insert({'challenge_id': challenge_id, 'user_id': user_id, 'current_value': value}).execute()

# ▼▼▼ [신규] 챌린지 인증 내역을 DB에 저장하는 함수 ▼▼▼
async def create_submission(db: AsyncClient, challenge_id: int, user_id: str, content: Optional[str], image_url: Optional[str]) -> Dict[str, Any]:
    """challenge_submissions 테이블에 새로운 인증 기록을 생성합니다."""
    response = await db.table('challenge_submissions').insert({
        'challenge_id': challenge_id,
        'user_id': user_id,
        'proof_content': content,
        'proof_image_url': image_url,
        'status': 'pending',
    }).execute()

    # ✨ [핵심 수정]
    # response.data가 비어있는지 확인하여 오류를 방지합니다.
    if not response.data:
        raise Exception("데이터베이스에 인증 내역을 저장하지 못했습니다. 테이블 이름이나 컬럼을 확인해주세요.")

    return response.data[0]

# ▼▼▼ [신규] 이미지를 Supabase 스토리지에 업로드하는 함수 ▼▼▼
async def upload_challenge_image(db: AsyncClient, user_id: str, image_base64: str) -> str:
    """Base64 인코딩된 이미지를 디코딩하여 Supabase 스토리지에 업로드하고 public URL을 반환합니다."""
    try:
        # 1. Base64 데이터를 이미지 바이너리로 디코딩
        image_data = base64.b64decode(image_base64)

        # 2. 파일 경로 및 이름 지정 (중복을 피하기 위해 timestamp 사용)
        file_path = f"challenge_proofs/{user_id}/{datetime.now().timestamp()}.jpg"
        bucket_name = 'images' # Supabase 스토리지의 버킷 이름

        # 3. 이미지 업로드
        await db.storage.from_(bucket_name).upload(file_path, image_data, {"content-type": "image/jpeg"})

        # 4. 업로드된 파일의 Public URL 가져오기
        response = await db.storage.from_(bucket_name).get_public_url(file_path)

        # Supabase-py v1 에서는 response가 URL 문자열, v2 에서는 객체일 수 있음
        public_url = response if isinstance(response, str) else response['publicURL']

        return public_url

    except Exception as e:
        print(f"이미지 업로드 실패: {e}")
        raise