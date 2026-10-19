import asyncio
import base64
from datetime import datetime, timedelta, timezone
from typing import List, Optional, Dict, Any
import logging
from supabase import AsyncClient
from models.challenge_model import ChallengeCreate, ChallengeUpdate


async def create_study_group(
        db: AsyncClient,
        name: str,
        description: Optional[str],
        created_by: str,
        max_members: int,
        requires_approval: bool
) -> Dict[str, Any]:
    """학습 그룹 생성"""
    response = await db.table('study_groups').insert({
        'name': name,
        'description': description,
        'created_by': created_by,
        'max_members': max_members,
        'requires_approval': requires_approval
    }).execute()

    group_id = response.data[0]['id']

    await db.table('group_members').insert({
        'group_id': group_id,
        'user_id': created_by,
        'role': 'owner'
    }).execute()

    return response.data[0]

async def get_all_study_groups(db: AsyncClient, current_user_id: str) -> List[Dict[str, Any]]:
    """모든 활성 그룹 조회 (현재 사용자의 멤버십 정보 포함)"""
    groups_response = await db.table('study_groups') \
        .select('*, user_account!created_by(name)') \
        .eq('is_active', True) \
        .order('created_at', desc=True) \
        .execute()

    groups = []
    for group in groups_response.data:
        members_response = await db.table('group_members') \
            .select('user_id, role', count='exact') \
            .eq('group_id', group['id']) \
            .execute()

        member_count = members_response.count
        is_member = any(m['user_id'] == current_user_id for m in members_response.data)
        is_owner = any(m['user_id'] == current_user_id and m['role'] == 'owner'
                       for m in members_response.data)

        groups.append({
            **group,
            'member_count': member_count,
            'is_member': is_member,
            'is_owner': is_owner,
            'creator_name': group['user_account']['name'] if group.get('user_account') else None
        })

    return groups

async def join_study_group(db: AsyncClient, group_id: int, user_id: str) -> str:
    """그룹 참여 또는 참여 요청"""
    group_res = await db.table('study_groups').select('max_members, requires_approval').eq('id', group_id).single().execute()
    group = group_res.data

    members_res = await db.table('group_members').select('user_id', count='exact').eq('group_id', group_id).execute()

    if members_res.count >= group['max_members']:
        raise Exception('그룹 인원이 가득 찼습니다.')

    if group['requires_approval']:
        req_res = await db.table('study_group_join_requests').select('id').eq('group_id', group_id).eq('user_id', user_id).eq('status', 'pending').execute()
        if req_res.data:
            raise Exception('이미 가입을 요청했습니다.')

        await db.table('study_group_join_requests').insert({
            'group_id': group_id,
            'user_id': user_id,
            'status': 'pending'
        }).execute()
        return "가입 요청이 완료되었습니다. 그룹장의 승인을 기다려주세요."
    else:
        await db.table('group_members').insert({
            'group_id': group_id,
            'user_id': user_id,
            'role': 'member'
        }).execute()
        return "그룹에 참여했습니다."

async def leave_study_group(db: AsyncClient, group_id: int, user_id: str) -> bool:
    """그룹 탈퇴"""
    member = await db.table('group_members') \
        .select('role') \
        .eq('group_id', group_id) \
        .eq('user_id', user_id) \
        .single() \
        .execute()

    if member.data['role'] == 'owner':
        raise Exception('그룹 소유자는 탈퇴할 수 없습니다.')

    await db.table('group_members') \
        .delete() \
        .eq('group_id', group_id) \
        .eq('user_id', user_id) \
        .execute()

    return True

async def get_group_members(db: AsyncClient, group_id: int) -> List[Dict[str, Any]]:
    """그룹 멤버 목록 조회"""
    response = await db.table('group_members') \
        .select('user_id, role, joined_at, user_account(name)') \
        .eq('group_id', group_id) \
        .order('joined_at') \
        .execute()

    members = []
    for member in response.data:
        members.append({
            'user_id': member['user_id'],
            'user_name': member['user_account']['name'] if member.get('user_account') else 'Unknown',
            'role': member['role'],
            'joined_at': member['joined_at']
        })

    return members

async def delete_study_group(db: AsyncClient, group_id: int, user_id: str) -> bool:
    """그룹 삭제 (owner만 가능)"""
    member = await db.table('group_members') \
        .select('role') \
        .eq('group_id', group_id) \
        .eq('user_id', user_id) \
        .single() \
        .execute()

    if member.data['role'] != 'owner':
        raise Exception('그룹 삭제 권한이 없습니다.')

    await db.table('study_groups') \
        .update({'is_active': False}) \
        .eq('id', group_id) \
        .execute()

    return True

async def get_group_messages(db: AsyncClient, group_id: int) -> List[Dict[str, Any]]:
    """그룹 채팅 메시지 목록 조회"""
    response = await db.table('study_group_messages') \
        .select('*, user_account(name)') \
        .eq('group_id', group_id) \
        .order('created_at', desc=False) \
        .limit(100) \
        .execute()

    messages = []
    for msg in response.data:
        user_name = "알 수 없는 사용자"
        user_account_info = msg.get('user_account')
        if user_account_info and user_account_info.get('name'):
            user_name = user_account_info['name']

        messages.append({
            'id': msg['id'],
            'group_id': msg['group_id'],
            'user_id': msg['user_id'],
            'user_name': user_name,
            'content': msg['content'],
            'created_at': msg['created_at']
        })
    return messages

async def create_group_message(db: AsyncClient, group_id: int, user_id: str, content: str) -> Dict[str, Any]:
    """그룹 채팅 메시지 생성"""
    try:
        await asyncio.sleep(0.01)
        response = await db.table('study_group_messages').insert({
            'group_id': group_id,
            'user_id': user_id,
            'content': content
        }).execute()

        if not response.data:
            raise Exception("메시지 삽입 후 데이터가 반환되지 않았습니다.")

        return response.data[0]
    except Exception as e:
        raise Exception(f"create_group_message DB 작업 실패: {e}")

async def get_join_requests(db: AsyncClient, group_id: int) -> List[Dict[str, Any]]:
    """특정 그룹의 'pending' 상태인 가입 요청 목록 조회"""
    try:
        response = await db.table('study_group_join_requests') \
            .select('*, user_account(name)') \
            .eq('group_id', group_id) \
            .eq('status', 'pending') \
            .order('created_at', desc=True) \
            .execute()

        if not response.data:
            return []

        requests = []
        for req in response.data:
            requests.append({
                'request_id': req['id'],
                'user_id': req['user_id'],
                'user_name': req.get('user_account', {}).get('name') if req.get('user_account') else 'Unknown',
                'requested_at': req['created_at']
            })
        return requests
    except Exception as e:
        print(f"--- [DB] 데이터베이스 쿼리 중 심각한 오류 발생 ---")
        print(e)
        raise e

async def process_join_request(db: AsyncClient, request_id: int, new_status: str) -> bool:
    """가입 요청 처리 (승인 또는 거절)"""
    req_res = await db.table('study_group_join_requests').select('group_id, user_id, status').eq('id', request_id).single().execute()
    if not req_res.data or req_res.data['status'] != 'pending':
        raise Exception('처리할 수 없는 요청입니다.')

    request_data = req_res.data

    if new_status == 'approved':
        group_res = await db.table('study_groups').select('max_members').eq('id', request_data['group_id']).single().execute()
        members_res = await db.table('group_members').select('user_id', count='exact').eq('group_id', request_data['group_id']).execute()

        if members_res.count >= group_res.data['max_members']:
            raise Exception('그룹 인원이 가득 찼습니다.')

        await db.table('group_members').insert({
            'group_id': request_data['group_id'],
            'user_id': request_data['user_id'],
            'role': 'member'
        }).execute()

    await db.table('study_group_join_requests').update({'status': new_status}).eq('id', request_id).execute()
    return True

async def get_group_owner(db: AsyncClient, group_id: int) -> Optional[str]:
    """그룹 소유자의 user_id를 반환"""
    owner_res = await db.table('group_members') \
        .select('user_id') \
        .eq('group_id', group_id) \
        .eq('role', 'owner') \
        .maybe_single() \
        .execute()
    return owner_res.data['user_id'] if owner_res.data else None

async def create_challenge(db: AsyncClient, group_id: int, user_id: str, challenge_data: ChallengeCreate) -> Dict[str, Any]:
    """group_challenges 테이블에 새로운 자유 형식 챌린지 생성"""
    end_date = datetime.now(timezone.utc) + timedelta(days=challenge_data.duration_days)

    response = await db.table('group_challenges').insert({
        'group_id': group_id,
        'created_by_user_id': user_id,
        'title': challenge_data.title,
        'description': challenge_data.description,
        'end_date': end_date.isoformat(),
    }).execute()

    return response.data[0]

# ▼▼▼ [수정 완료] get_challenges_by_group_id 함수 ▼▼▼
async def get_challenges_by_group_id(db: AsyncClient, group_id: int, current_user_id: str) -> List[Dict[str, Any]]:
    """특정 그룹의 모든 챌린지와 완료한 참여자 정보 조회 (최적화 버전)"""
    challenges_res = await db.table('group_challenges') \
        .select('*, creator:user_account!created_by_user_id(name)') \
        .eq('group_id', group_id) \
        .order('end_date', desc=True) \
        .execute()

    if not challenges_res.data:
        return []

    challenges = challenges_res.data
    challenge_ids = [c['id'] for c in challenges]

    participants_res = await db.table('challenge_participants') \
        .select('challenge_id, user_id, completed_at, user_account(name)') \
        .in_('challenge_id', challenge_ids) \
        .eq('status', 'approved') \
        .execute()

    participants_data = participants_res.data

    participants_by_challenge = {cid: [] for cid in challenge_ids}
    for p in participants_data:
        if p.get('user_account'):
            participants_by_challenge[p['challenge_id']].append({
                'user_id': p['user_id'],
                'user_name': p['user_account']['name'],
                'completed_at': p['completed_at']
            })

    response_data = []
    for challenge in challenges:
        challenge_id = challenge['id']
        participants = participants_by_challenge.get(challenge_id, [])
        user_has_completed = any(p['user_id'] == current_user_id for p in participants)

        # [핵심 수정] **challenge 대신, 필드를 명시적으로 매핑합니다.
        response_data.append({
            'id': challenge['id'],
            'group_id': challenge['group_id'],
            'creator_id': challenge['created_by_user_id'], # DB 컬럼명을 모델 필드명으로 변경
            'creator_name': challenge.get('creator', {}).get('name', 'Unknown'),
            'title': challenge['title'],
            'description': challenge['description'],
            'end_date': challenge['end_date'],
            'created_at': challenge['created_at'],
            'participants': participants,
            'user_has_completed': user_has_completed,
        })

    return response_data

async def create_challenge_submission(db: AsyncClient, challenge_id: int, user_id: str, content: str, image_url: Optional[str]) -> Dict[str, Any]:
    """챌린지 인증 제출"""
    existing_sub = await db.table('challenge_submissions') \
        .select('id, status') \
        .eq('challenge_id', challenge_id) \
        .eq('user_id', user_id) \
        .in_('status', ['pending', 'approved']) \
        .execute()

    if existing_sub.data:
        raise Exception(f"이미 '{existing_sub.data[0]['status']}' 상태의 인증 내역이 존재합니다.")

    response = await db.table('challenge_submissions').insert({
        'challenge_id': challenge_id,
        'user_id': user_id,
        'proof_content': content,
        'proof_image_url': image_url
    }).execute()
    return response.data[0]

async def get_submissions_for_challenge(db: AsyncClient, challenge_id: int) -> List[Dict[str, Any]]:
    """특정 챌린지의 모든 인증 내역 조회 (그룹장용)"""
    response = await db.table('challenge_submissions') \
        .select('*, user_account(name)') \
        .eq('challenge_id', challenge_id) \
        .order('submitted_at', desc=True) \
        .execute()
    return response.data

async def process_submission(db: AsyncClient, submission_id: int, new_status: str) -> Dict[str, Any]:
    """인증 승인/거절 처리 (수정됨)"""

    # 1. 먼저, 처리할 인증 내역을 조회하여 정보를 가져옵니다.
    submission_res = await db.table('challenge_submissions') \
        .select('challenge_id, user_id, status') \
        .eq('id', submission_id) \
        .maybe_single() \
        .execute()

    if not submission_res.data:
        raise Exception("존재하지 않는 인증 내역입니다.")

    submission_info = submission_res.data

    # 이미 처리된 요청인지 확인하여 중복 처리를 방지합니다.
    if submission_info['status'] != 'pending':
        raise Exception(f"이미 '{submission_info['status']}' 상태인 인증입니다.")

    # 2. 인증 내역의 상태를 'approved' 또는 'rejected'로 업데이트합니다.
    await db.table('challenge_submissions') \
        .update({'status': new_status}) \
        .eq('id', submission_id) \
        .execute()

    # 3. 만약 '승인(approved)'된 경우, challenge_participants 테이블에도 기록합니다.
    if new_status == 'approved':
        # 이미 참여자로 기록되었는지 중복 확인
        existing_participant = await db.table('challenge_participants') \
            .select('id') \
            .eq('challenge_id', submission_info['challenge_id']) \
            .eq('user_id', submission_info['user_id']) \
            .execute()

        # 기록이 없을 때만 새로 추가합니다.
        if not existing_participant.data:
            await db.table('challenge_participants').insert({
                'challenge_id': submission_info['challenge_id'],
                'user_id': submission_info['user_id'],
                'status': 'approved' # participant 테이블에도 상태 기록
            }).execute()

    # 성공적으로 처리되었음을 알리기 위해 원래 submission 정보를 반환합니다.
    return submission_info

async def get_challenge_by_id(db: AsyncClient, challenge_id: int) -> Dict[str, Any]:
    """ID로 단일 챌린지 조회 (권한 확인용)"""
    response = await db.table('group_challenges').select('*').eq('id', challenge_id).maybe_single().execute()
    return response.data

async def update_challenge(db: AsyncClient, challenge_id: int, update_data: Dict[str, Any]) -> Dict[str, Any]:
    """챌린지 정보 업데이트"""
    response = await db.table('group_challenges').update(update_data).eq('id', challenge_id).execute()
    return response.data[0]

async def delete_challenge(db: AsyncClient, challenge_id: int):
    """챌린지 삭제"""
    await db.table('group_challenges').delete().eq('id', challenge_id).execute()

async def is_user_group_member(db: AsyncClient, group_id: int, user_id: str) -> bool:
    """사용자가 특정 그룹의 멤버인지 확인합니다."""
    response = await db.table('group_members') \
        .select('user_id', count='exact') \
        .eq('group_id', group_id) \
        .eq('user_id', user_id) \
        .execute()

    return response.count > 0

async def log_progress(db: AsyncClient, user_id: str, log_type: str, value: int):
    """
    사용자의 모든 활성 챌린지에 진행률을 업데이트합니다.
    (챌린지 유형(type)을 더 이상 구분하지 않습니다.)
    """
    try:
        now_utc = datetime.now(timezone.utc).isoformat()

        # 1. 사용자가 참여하고 있고, 아직 마감되지 않은 '모든' 챌린지를 찾습니다.
        #    'challenge_type' 필터링 로직을 제거했습니다.
        participants_response = await db.table('challenge_participants') \
            .select('id, progress, group_challenges!inner(id)') \
            .eq('user_id', user_id) \
            .gt('group_challenges.end_date', now_utc) \
            .execute()

        if not participants_response.data:
            logging.info(f"사용자 {user_id}에 대한 활성 챌린지가 없습니다. 진행률 업데이트를 건너뜁니다.")
            return

        # 2. 찾은 모든 챌린지에 대해 진행률을 업데이트합니다.
        for participant in participants_response.data:
            participant_id = participant['id']
            # challenge_progress 테이블이 없으므로 challenge_participants 테이블을 사용한다고 가정합니다.
            current_progress = participant.get('progress') or 0
            new_progress = current_progress + value

            await db.table('challenge_participants') \
                .update({'progress': new_progress}) \
                .eq('id', participant_id) \
                .execute()

            logging.info(f"챌린지 진행률 업데이트 성공: participant_id={participant_id}, new_progress={new_progress}")

    except Exception as e:
        logging.error(f"챌린지 진행률 업데이트 중 오류 발생 (user_id: {user_id}): {e}")
        # 오류를 다시 발생시켜 API 레이어에서 500 에러로 처리하도록 합니다.
        raise

async def upload_challenge_image(db: AsyncClient, user_id: str, image_base64: str) -> str:
    """Base64 인코딩된 이미지를 디코딩하여 Supabase 스토리지에 업로드하고 public URL을 반환합니다."""
    try:
        image_data = base64.b64decode(image_base64)
        file_path = f"challenge_proofs/{user_id}/{datetime.now().timestamp()}.jpg"
        bucket_name = 'images'

        await db.storage.from_(bucket_name).upload(
            path=file_path,
            file=image_data,
            file_options={"content-type": "image/jpeg"}
        )

        # ✨👇 [핵심 수정] await 키워드를 추가합니다.
        public_url = await db.storage.from_(bucket_name).get_public_url(file_path)

        return public_url

    except Exception as e:
        logging.error(f"이미지 업로드 실패: {e}")
        # 오류를 다시 발생시켜 API 레이어에서 처리하도록 합니다.
        raise

async def create_submission(db: AsyncClient, challenge_id: int, user_id: str, content: Optional[str], image_url: Optional[str]) -> Dict[str, Any]:
    """challenge_submissions 테이블에 새로운 인증 기록을 생성합니다."""
    response = await db.table('challenge_submissions').insert({
        'challenge_id': challenge_id,
        'user_id': user_id,
        'proof_content': content,
        'proof_image_url': image_url,
        'status': 'pending',
    }).execute()

    if not response.data:
        raise Exception("DB에 인증 내역을 저장하지 못했습니다. 테이블 RLS 정책이나 컬럼을 확인해주세요.")

    return response.data[0]

async def get_user_submission_for_challenge(db: AsyncClient, challenge_id: int, user_id: str) -> Optional[Dict[str, Any]]:
    """특정 챌린지에 대한 현재 사용자의 가장 최근 인증 내역을 조회합니다."""
    try:
        response = await db.table('challenge_submissions') \
            .select('*, user_account(name)') \
            .eq('challenge_id', challenge_id) \
            .eq('user_id', user_id) \
            .order('submitted_at', desc=True) \
            .limit(1) \
            .maybe_single() \
            .execute()

        # ✨ [핵심 수정]
        # response 객체가 None이 아닌지 먼저 확인합니다.
        if response:
            return response.data

        # response가 None이면, 데이터가 없는 것이므로 None을 반환합니다.
        return None

    except Exception as e:
        logging.error(f"내 인증 내역 조회 중 DB 오류 발생: {e}")
        return None

async def update_submission(db: AsyncClient, submission_id: int, user_id: str, content: Optional[str], image_url: Optional[str]) -> Dict[str, Any]:
    """사용자가 본인의 챌린지 인증 내역을 수정하고, participants 테이블의 완료 기록도 삭제합니다."""
    update_values = {
        'proof_content': content,
        'proof_image_url': image_url,
        'status': 'pending', # 수정 시 다시 '승인 대기중' 상태로 변경
    }

    # 1. challenge_submissions 테이블을 업데이트하고, challenge_id를 받아옵니다.
    response = await db.table('challenge_submissions') \
        .update(update_values) \
        .eq('id', submission_id) \
        .eq('user_id', user_id) \
        .select('*') \
        .execute()

    if not response.data:
        raise Exception("수정할 인증 내역을 찾을 수 없거나 권한이 없습니다.")

    updated_submission = response.data[0]
    challenge_id = updated_submission['challenge_id']

    # ✨ 2. [핵심 로직 추가] challenge_participants 테이블에서 해당 유저의 '완료' 기록을 삭제합니다.
    await db.table('challenge_participants') \
        .delete() \
        .eq('challenge_id', challenge_id) \
        .eq('user_id', user_id) \
        .execute()

    logging.info(f"챌린지 참여자 기록 삭제: challenge_id={challenge_id}, user_id={user_id}")

    return updated_submission


async def delete_submission(db: AsyncClient, submission_id: int, user_id: str):
    """사용자가 본인의 챌린지 인증 내역과 참여자 기록을 함께 삭제합니다."""

    # 1. 먼저 삭제할 인증 내역을 조회하여 challenge_id를 확보합니다.
    submission_to_delete_res = await db.table('challenge_submissions') \
        .select('challenge_id, user_id') \
        .eq('id', submission_id) \
        .eq('user_id', user_id) \
        .maybe_single() \
        .execute()

    if not submission_to_delete_res.data:
        # 이미 삭제되었거나 대상이 없는 경우 조용히 종료하거나 예외를 발생시킬 수 있습니다.
        # 여기서는 조용히 종료하여, 사용자가 중복으로 삭제 버튼을 눌러도 오류가 나지 않도록 합니다.
        logging.warning(f"삭제할 인증 내역(id:{submission_id})을 찾을 수 없거나 권한이 없습니다.")
        return

    submission_info = submission_to_delete_res.data
    challenge_id = submission_info['challenge_id']

    # 2. challenge_submissions 테이블에서 인증 내역을 삭제합니다.
    await db.table('challenge_submissions') \
        .delete() \
        .eq('id', submission_id) \
        .execute()

    # ✨ 3. [핵심 로직] challenge_participants 테이블에서도 해당 유저의 '완료' 기록을 삭제합니다.
    await db.table('challenge_participants') \
        .delete() \
        .eq('challenge_id', challenge_id) \
        .eq('user_id', user_id) \
        .execute()

    logging.info(f"챌린지 참여자 기록 삭제 (인증 삭제로 인한): challenge_id={challenge_id}, user_id={user_id}")

    # 성공적으로 삭제되었음을 알리기 위해 삭제된 submission 정보를 반환합니다.
    return submission_info

async def get_submission_by_id(db: AsyncClient, submission_id: int) -> Optional[Dict[str, Any]]:
    """ID로 단일 인증 내역을 조회합니다 (권한 확인을 위해 챌린지 정보와 함께)."""
    response = await db.table('challenge_submissions') \
        .select('*, challenge:group_challenges(group_id)') \
        .eq('id', submission_id) \
        .maybe_single() \
        .execute()
    return response.data

async def get_challenge_participants(db: AsyncClient, challenge_id: int) -> List[Dict[str, Any]]:
    """특정 챌린지를 완료(승인)한 참여자 목록을 조회합니다."""
    response = await db.table('challenge_participants') \
        .select('user_id, completed_at, user_account(name)') \
        .eq('challenge_id', challenge_id) \
        .eq('status', 'approved') \
        .order('completed_at', desc=True) \
        .execute()

    if not response.data:
        return []

    # API 응답 모델에 맞게 데이터 가공
    participants = []
    for p in response.data:
        if p.get('user_account'): # user_account 정보가 있는 경우에만 추가
            participants.append({
                'user_id': p['user_id'],
                'user_name': p['user_account']['name'],
                'completed_at': p['completed_at']
            })
    return participants