# services/community_service.py

from typing import Optional

from fastapi import HTTPException
from supabase import AsyncClient

from db import community_supabase
from models import community_model


# ====== 게시글 (Post) ======
async def create_new_post(db: AsyncClient, post: community_model.PostCreate, user_id: str):
    return await community_supabase.create_post(db, post, user_id)

async def get_all_posts(db: AsyncClient, category: str, search: Optional[str] = None):
    return await community_supabase.get_all_posts(db, category, search)

async def get_post_by_id(db: AsyncClient, post_id: int):
    post = await community_supabase.get_post_by_id(db, post_id)
    if not post:
        # [수정] 게시글이 없을 경우 404 예외 발생
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다.")
    return post

async def update_existing_post(db: AsyncClient, post_id: int, post_update: community_model.PostUpdate, current_user: dict):
    post = await get_post_by_id(db, post_id) # 수정된 get_post_by_id 사용
    # [수정] 권한이 없을 경우 403 Forbidden 예외 발생
    if not current_user.get('is_admin') and post.get('user_id') != current_user.get('user_id'):
        raise HTTPException(status_code=403, detail="게시글을 수정할 권한이 없습니다.")
    return await community_supabase.update_post(db, post_id, post_update)

async def delete_existing_post(db: AsyncClient, post_id: int, current_user: dict):
    post = await get_post_by_id(db, post_id) # 수정된 get_post_by_id 사용
    # [수정] 권한이 없을 경우 403 Forbidden 예외 발생
    if not current_user.get('is_admin') and post.get('user_id') != current_user.get('user_id'):
        raise HTTPException(status_code=403, detail="게시글을 삭제할 권한이 없습니다.")
    return await community_supabase.delete_post(db, post_id)

# ====== 댓글 (Comment) ======
async def create_new_comment(db: AsyncClient, comment: community_model.CommentCreate, post_id: int, user_id: str):
    return await community_supabase.create_comment(db, comment, post_id, user_id)

async def get_all_comments_for_post(db: AsyncClient, post_id: int):
    return await community_supabase.get_comments_by_post_id(db, post_id)

# ▼▼▼ [신규] 댓글 수정을 위한 서비스 함수 ▼▼▼
async def update_existing_comment(db: AsyncClient, comment_id: int, comment_update: community_model.CommentUpdate, current_user: dict):
    comment = await community_supabase.get_comment_by_id(db, comment_id)
    if not comment:
        # [수정] 댓글이 없을 경우 404 예외 발생
        raise HTTPException(status_code=404, detail="댓글을 찾을 수 없습니다.")
    if not current_user.get('is_admin') and comment.get('user_id') != current_user.get('user_id'):
        # [수정] 권한이 없을 경우 403 Forbidden 예외 발생
        raise HTTPException(status_code=403, detail="댓글을 수정할 권한이 없습니다.")
    return await community_supabase.update_comment(db, comment_id, comment_update)

async def delete_existing_comment(db: AsyncClient, comment_id: int, current_user: dict):
    comment = await community_supabase.get_comment_by_id(db, comment_id)
    if not comment:
        raise HTTPException(status_code=404, detail="댓글을 찾을 수 없습니다.")
    if not current_user.get('is_admin') and comment.get('user_id') != current_user.get('user_id'):
        raise HTTPException(status_code=403, detail="댓글을 삭제할 권한이 없습니다.")
    return await community_supabase.delete_comment(db, comment_id)

# ====== 신고 (Report) ======
async def create_new_report(db: AsyncClient, report: community_model.ReportCreate, user_id: str):
    return await community_supabase.create_report(db, report, user_id)

async def get_all_reports(db: AsyncClient):
    return await community_supabase.get_all_reports(db)
