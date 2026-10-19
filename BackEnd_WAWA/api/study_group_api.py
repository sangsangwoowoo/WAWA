from typing import List, Optional

from fastapi import APIRouter, HTTPException, Depends, status, UploadFile, File, Form, Query
from supabase import AsyncClient

from core.database import get_db
from core.dependencies import get_current_user
from db import study_group_supabase
from models.challenge_model import ChallengeCreate, ChallengeResponse, ProgressLogRequest, ChallengeUpdate, ChallengeSubmissionResponse, SubmissionCreate, ChallengeParticipant
from models.study_group_model import StudyGroupCreate, StudyGroupResponse, GroupMemberResponse, GroupMessageCreate, \
    GroupMessageResponse, JoinRequestResponse

router = APIRouter()

@router.post("/create", response_model=StudyGroupResponse)
async def create_study_group(
        group: StudyGroupCreate,
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """학습 그룹 생성"""
    try:
        user_id = current_user.get('user_id')
        user_name = current_user.get('name') # 생성자 이름을 가져옵니다.

        group_data = await study_group_supabase.create_study_group(
            db=db,
            name=group.name,
            description=group.description,
            created_by=user_id,
            max_members=group.max_members,
            requires_approval=group.requires_approval
        )

        return StudyGroupResponse(
            id=group_data['id'],
            name=group_data['name'],
            description=group_data['description'],
            created_by=group_data['created_by'],
            creator_name=user_name, # 여기서 생성자 이름을 넣어줍니다.
            max_members=group_data['max_members'],
            member_count=1,
            is_member=True,
            is_owner=True,
            requires_approval=group_data['requires_approval'],
            created_at=group_data['created_at']
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/list", response_model=List[StudyGroupResponse])
async def get_study_groups(
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """모든 학습 그룹 조회"""
    try:
        user_id = current_user.get('user_id')
        groups = await study_group_supabase.get_all_study_groups(db, user_id)
        return [StudyGroupResponse(**group) for group in groups]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/{group_id}/join")
async def join_group(
        group_id: int,
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """그룹 참여"""
    try:
        user_id = current_user.get('user_id')
        message = await study_group_supabase.join_study_group(db, group_id, user_id)
        return {"message": message}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.delete("/{group_id}/leave")
async def leave_group(
        group_id: int,
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """그룹 탈퇴"""
    try:
        user_id = current_user.get('user_id')
        await study_group_supabase.leave_study_group(db, group_id, user_id)
        return {"message": "그룹에서 탈퇴했습니다."}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/{group_id}/members", response_model=List[GroupMemberResponse])
async def get_group_members(
        group_id: int,
        # 그룹 멤버는 누구나 볼 수 있으므로 current_user 인증이 필수는 아닐 수 있습니다.
        # 만약 그룹 멤버만 보게 하려면 Depends(get_current_user)를 유지합니다.
        db: AsyncClient = Depends(get_db)
):
    """그룹 멤버 조회"""
    try:
        members = await study_group_supabase.get_group_members(db, group_id)
        return [GroupMemberResponse(**member) for member in members]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/{group_id}")
async def delete_group(
        group_id: int,
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """그룹 삭제 (owner 전용)"""
    try:
        user_id = current_user.get('user_id')
        await study_group_supabase.delete_study_group(db, group_id, user_id)
        return {"message": "그룹이 삭제되었습니다."}
    except Exception as e:
        raise HTTPException(status_code=403, detail=str(e))

# ==========================================================
# ▼▼▼ 여기가 정리된 올바른 메시지 관련 함수들입니다. ▼▼▼
# ==========================================================

@router.get("/{group_id}/messages", response_model=List[GroupMessageResponse])
async def get_group_messages(
        group_id: int,
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """그룹 채팅 메시지 조회"""
    # 실제 프로덕션에서는 이 유저가 그룹 멤버인지 확인하는 로직이 추가되어야 합니다.
    try:
        messages = await study_group_supabase.get_group_messages(db, group_id)
        return [GroupMessageResponse(**msg) for msg in messages]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/{group_id}/messages", response_model=GroupMessageResponse)
async def post_group_message(
        group_id: int,
        message: GroupMessageCreate,
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """그룹 채팅 메시지 작성"""
    try:
        user_id = current_user.get('user_id')
        user_name = current_user.get('name', 'Unknown')

        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid user token.")

        new_msg = await study_group_supabase.create_group_message(
            db=db,
            group_id=group_id,
            user_id=user_id,
            content=message.content
        )

        response_data = GroupMessageResponse(
            id=new_msg['id'],
            group_id=new_msg['group_id'],
            user_id=new_msg['user_id'],
            user_name=user_name,
            content=new_msg['content'],
            created_at=new_msg['created_at']
        )

        return response_data

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"서버 내부 오류 발생: {str(e)}")


# ==========================================================
# ▲▲▲ 메시지 관련 함수 끝 ▲▲▲
# ==========================================================

@router.get("/{group_id}/requests", response_model=List[JoinRequestResponse])
async def get_pending_requests(
        group_id: int,
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """그룹 가입 요청 목록 조회 (그룹장 전용)"""
    try:
        owner_id = await study_group_supabase.get_group_owner(db, group_id)
        if owner_id != current_user.get('user_id'):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="권한이 없습니다.")

        requests = await study_group_supabase.get_join_requests(db, group_id)
        return [JoinRequestResponse(**req) for req in requests]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/{group_id}/requests/{request_id}/approve")
async def approve_request(
        group_id: int,
        request_id: int,
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """가입 요청 승인 (그룹장 전용)"""
    try:
        owner_id = await study_group_supabase.get_group_owner(db, group_id)
        if owner_id != current_user.get('user_id'):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="권한이 없습니다.")

        await study_group_supabase.process_join_request(db, request_id, 'approved')
        return {"message": "가입 요청을 승인했습니다."}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/{group_id}/requests/{request_id}/reject")
async def reject_request(
        group_id: int,
        request_id: int,
        current_user: dict = Depends(get_current_user),
        db: AsyncClient = Depends(get_db)
):
    """가입 요청 거절 (그룹장 전용)"""
    try:
        owner_id = await study_group_supabase.get_group_owner(db, group_id)
        if owner_id != current_user.get('user_id'):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="권한이 없습니다.")

        await study_group_supabase.process_join_request(db, request_id, 'rejected')
        return {"message": "가입 요청을 거절했습니다."}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/{group_id}/challenges", response_model=ChallengeResponse)
async def create_challenge(
        group_id: int,
        challenge_in: ChallengeCreate,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get('user_id')
    user_name = current_user.get('name', 'Unknown')

    is_member = await study_group_supabase.is_user_group_member(db, group_id, user_id)
    if not is_member:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="그룹 멤버만 챌린지를 생성할 수 있습니다.")

    new_challenge_data = await study_group_supabase.create_challenge(db, group_id, user_id, challenge_in)

    return ChallengeResponse(
        id=new_challenge_data['id'],
        group_id=new_challenge_data['group_id'],
        creator_id=new_challenge_data['created_by_user_id'],
        creator_name=user_name,
        title=new_challenge_data['title'],
        description=new_challenge_data['description'],
        end_date=new_challenge_data['end_date'],
        created_at=new_challenge_data['created_at'],
        participants=[], # 생성 시점에는 참여자 없음
        user_has_completed=False,
    )


@router.get("/{group_id}/challenges", response_model=List[ChallengeResponse])
async def list_challenges(
        group_id: int,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get('user_id')
    challenges = await study_group_supabase.get_challenges_by_group_id(db, group_id, user_id)
    return [ChallengeResponse(**c) for c in challenges]

@router.put("/challenges/{challenge_id}", response_model=ChallengeResponse)
async def update_challenge(
        challenge_id: int,
        challenge_in: ChallengeUpdate,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    """챌린지를 수정합니다 (생성자 전용)."""
    user_id = current_user.get('user_id')

    challenge = await study_group_supabase.get_challenge_by_id(db, challenge_id)
    if not challenge:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="챌린지를 찾을 수 없습니다.")
    if challenge['created_by_user_id'] != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="수정 권한이 없습니다.")

    updated_challenge = await study_group_supabase.update_challenge(db, challenge_id, challenge_in.model_dump(exclude_unset=True))

    # 수정 후 전체 데이터를 다시 조회해서 반환
    all_challenges = await study_group_supabase.get_challenges_by_group_id(db, updated_challenge['group_id'])
    for c in all_challenges:
        if c['id'] == challenge_id:
            return ChallengeResponse(**c)


@router.delete("/challenges/{challenge_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_challenge(
        challenge_id: int,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    """챌린지를 삭제합니다 (생성자 전용)."""
    user_id = current_user.get('user_id')

    challenge = await study_group_supabase.get_challenge_by_id(db, challenge_id)
    if not challenge:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="챌린지를 찾을 수 없습니다.")
    if challenge['created_by_user_id'] != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="삭제 권한이 없습니다.")

    await study_group_supabase.delete_challenge(db, challenge_id)

@router.post("/challenges/{challenge_id}/submit", status_code=status.HTTP_201_CREATED)
async def submit_challenge_proof(
        challenge_id: int,
        proof_content: Optional[str] = Form(None),
        proof_image: Optional[UploadFile] = File(None),
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    user_id = current_user.get('user_id')
    image_url = None

    # (주의) 실제 프로덕션에서는 파일 저장 로직이 필요합니다.
    # 예: S3, Supabase Storage 등에 업로드하고 URL을 받아오는 로직
    if proof_image:
        # file_path = f"challenge_proofs/{challenge_id}_{user_id}_{proof_image.filename}"
        # await storage_client.upload(file_path, proof_image.file)
        # image_url = storage_client.get_public_url(file_path)
        image_url = "https://example.com/placeholder.jpg" # 임시 URL

    if not proof_content and not image_url:
        raise HTTPException(status_code=400, detail="인증 내용 또는 이미지가 필요합니다.")

    try:
        await study_group_supabase.create_challenge_submission(db, challenge_id, user_id, proof_content, image_url)
        return {"message": "인증 내역이 성공적으로 제출되었습니다. 그룹장의 승인을 기다려주세요."}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# ▼▼▼ [신규] 인증 내역 조회 API (그룹장용) ▼▼▼
@router.get("/challenges/{challenge_id}/submissions", response_model=List[ChallengeSubmissionResponse])
async def get_challenge_submissions(
        challenge_id: int,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    challenge = await study_group_supabase.get_challenge_by_id(db, challenge_id)
    if not challenge:
        raise HTTPException(status_code=404, detail="챌린지를 찾을 수 없습니다.")

    group_owner = await study_group_supabase.get_group_owner(db, challenge['group_id'])
    if group_owner != current_user.get('user_id'):
        raise HTTPException(status_code=403, detail="인증 내역을 조회할 권한이 없습니다.")

    submissions = await study_group_supabase.get_submissions_for_challenge(db, challenge_id)

    return [
        ChallengeSubmissionResponse(
            id=s['id'],
            user_id=s['user_id'],
            user_name=s.get('user_account', {}).get('name', 'Unknown'),
            proof_content=s['proof_content'],
            proof_image_url=s['proof_image_url'],
            status=s['status'],
            submitted_at=s['submitted_at']
        ) for s in submissions
    ]

# ▼▼▼ [신규] 인증 승인/거절 API (그룹장용) ▼▼▼
@router.post("/submissions/{submission_id}/process", status_code=status.HTTP_200_OK)
async def process_challenge_submission(
        submission_id: int,
        status: str = Query(..., pattern="^(approved|rejected)$"), # approved 또는 rejected만 허용
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    """인증 승인/거절 처리 (그룹장 전용)"""
    try:
        # 1. 제출된 인증 내역과 해당 그룹 ID를 조회합니다.
        submission = await study_group_supabase.get_submission_by_id(db, submission_id)
        if not submission or not submission.get('challenge'):
            raise HTTPException(status_code=404, detail="유효하지 않은 인증 내역입니다.")

        group_id = submission['challenge']['group_id']

        # 2. 현재 사용자가 해당 그룹의 장인지 확인합니다.
        group_owner = await study_group_supabase.get_group_owner(db, group_id)
        if group_owner != current_user.get('user_id'):
            raise HTTPException(status_code=403, detail="인증을 처리할 권한이 없습니다.")

        # 3. 권한이 확인되면, 기존의 승인/거절 로직을 실행합니다.
        await study_group_supabase.process_submission(db, submission_id, status)
        if status == 'approved':
            message = "인증을 승인했습니다."
        else: # 'rejected'
            message = "인증을 거절했습니다."

        return {"message": message}
    except Exception as e:
        # DB 함수에서 발생한 예외(예: 이미 처리된 요청)를 포함하여 처리합니다.
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/challenges/{challenge_id}/my-submission", response_model=Optional[ChallengeSubmissionResponse])
async def get_my_challenge_submission(
        challenge_id: int,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    """현재 사용자의 특정 챌린지에 대한 인증 내역을 조회합니다."""
    user_id = current_user.get('user_id')
    submission = await study_group_supabase.get_user_submission_for_challenge(db, challenge_id, user_id)

    if not submission:
        # 인증 내역이 없으면 204 No Content 응답을 보냅니다.
        return None

    # ChallengeSubmissionResponse 모델에 맞게 데이터를 가공하여 반환합니다.
    return ChallengeSubmissionResponse(
        id=submission['id'],
        user_id=submission['user_id'],
        user_name=submission.get('user_account', {}).get('name', 'Unknown'),
        proof_content=submission['proof_content'],
        proof_image_url=submission['proof_image_url'],
        status=submission['status'],
        submitted_at=submission['submitted_at']
    )

@router.put("/submissions/{submission_id}", response_model=ChallengeSubmissionResponse)
async def update_my_submission(
        submission_id: int,
        submission_in: SubmissionCreate, # 생성 시 사용했던 모델 재활용
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    """사용자 본인의 챌린지 인증을 수정합니다."""
    user_id = current_user.get('user_id')
    image_url = None

    try:
        # 새 이미지가 있으면 업로드
        if submission_in.proof_image_base64:
            image_url = await study_group_supabase.upload_challenge_image(db, user_id, submission_in.proof_image_base64)

        # DB 업데이트
        updated_submission = await study_group_supabase.update_submission(
            db, submission_id, user_id, submission_in.proof_content, image_url
        )

        # 상세 조회를 위한 데이터 재구성 (기존 코드 재활용)
        return ChallengeSubmissionResponse(
            id=updated_submission['id'],
            user_id=user_id,
            user_name=current_user.get('name', 'Unknown'),
            proof_content=updated_submission['proof_content'],
            proof_image_url=updated_submission['proof_image_url'],
            status=updated_submission['status'],
            submitted_at=updated_submission['submitted_at']
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"인증 수정 중 오류: {str(e)}")


@router.delete("/submissions/{submission_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_my_submission(
        submission_id: int,
        db: AsyncClient = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    """사용자 본인의 챌린지 인증을 삭제합니다."""
    user_id = current_user.get('user_id')
    try:
        await study_group_supabase.delete_submission(db, submission_id, user_id)
        # 성공 시 내용 없이 204 응답
    except Exception as e:
        raise HTTPException(status_code=404, detail=str(e))

@router.get("/challenges/{challenge_id}/participants", response_model=List[ChallengeParticipant])
async def list_challenge_participants(
        challenge_id: int,
        db: AsyncClient = Depends(get_db),
        # 이 API는 그룹 멤버 누구나 볼 수 있으므로 current_user 인증은 필수는 아님
        # (그룹 멤버만 보게 하려면 current_user: dict = Depends(get_current_user) 추가)
):
    """특정 챌린지를 완료한 멤버 목록을 조회합니다."""
    try:
        participants = await study_group_supabase.get_challenge_participants(db, challenge_id)
        return participants
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"참여자 목록 조회 중 오류: {str(e)}")