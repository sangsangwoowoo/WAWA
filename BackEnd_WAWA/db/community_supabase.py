# db/community_supabase.py

from typing import Optional

from supabase import AsyncClient

from models import community_model


# ====== 게시글 (Post) ======
async def create_post(db: AsyncClient, post: community_model.PostCreate, user_id: str):
    post_data = post.model_dump()
    post_data['user_id'] = user_id
    insert_response = await db.table("posts").insert(post_data).execute()
    if not insert_response.data: return None
    new_post_id = insert_response.data[0]['id']
    select_response = await db.table("posts").select("*, user_account(name)").eq("id", new_post_id).single().execute()
    return select_response.data

async def get_all_posts(db: AsyncClient, category: str, search: Optional[str] = None):
    query = db.table("posts").select("*, user_account(name)") \
        .eq("is_deleted", False) \
        .eq("category", category)

    if search:
        query = query.or_(f"title.ilike.%{search}%,content.ilike.%{search}%")

    response = await query.order("created_at", desc=True).execute()
    return response.data

async def get_post_by_id(db: AsyncClient, post_id: int):
    response = await db.table("posts").select("*, user_account(name)").eq("id", post_id).eq("is_deleted", False).maybe_single().execute()
    return response.data

async def update_post(db: AsyncClient, post_id: int, post_update: community_model.PostUpdate):
    update_data = post_update.model_dump(exclude_unset=True)
    update_response = await db.table("posts").update(update_data).eq("id", post_id).execute()
    if not update_response.data: return None
    select_response = await db.table("posts").select("*, user_account(name)").eq("id", post_id).single().execute()
    return select_response.data

async def delete_post(db: AsyncClient, post_id: int):
    response = await db.table("posts").update({"is_deleted": True}).eq("id", post_id).execute()
    return response.data[0] if response.data else None

# ====== 댓글 (Comment) ======
# ▼▼▼ [수정] 댓글 생성 시, 작성자 이름(user_account)까지 JOIN하여 반환 ▼▼▼
async def create_comment(db: AsyncClient, comment: community_model.CommentCreate, post_id: int, user_id: str):
    comment_data = comment.model_dump()
    comment_data['post_id'] = post_id
    comment_data['user_id'] = user_id
    insert_response = await db.table("comments").insert(comment_data).execute()
    if not insert_response.data:
        return None

    new_comment_id = insert_response.data[0]['id']
    select_response = await db.table("comments").select("*, user_account(name)").eq("id", new_comment_id).single().execute()
    return select_response.data

async def get_comments_by_post_id(db: AsyncClient, post_id: int):
    # is_deleted가 False인 댓글만 조회하도록 RLS(정책)를 설정하거나, 여기서 필터링합니다.
    # 여기서는 RLS가 설정되었다고 가정합니다.
    response = await db.table("comments").select("*, user_account(name)").eq("post_id", post_id).order("created_at", desc=False).execute()
    return response.data

# ▼▼▼ [신규] ID로 특정 댓글 하나를 조회하는 함수 (권한 확인용) ▼▼▼
async def get_comment_by_id(db: AsyncClient, comment_id: int):
    response = await db.table("comments").select("*").eq("id", comment_id).maybe_single().execute()
    return response.data

# ▼▼▼ [신규] 댓글 내용을 수정하는 함수 ▼▼▼
async def update_comment(db: AsyncClient, comment_id: int, comment_update: community_model.CommentUpdate):
    update_data = comment_update.model_dump()
    update_response = await db.table("comments").update(update_data).eq("id", comment_id).execute()
    if not update_response.data:
        return None

    select_response = await db.table("comments").select("*, user_account(name)").eq("id", comment_id).single().execute()
    return select_response.data

# ▼▼▼ [신규] 댓글을 논리적으로 삭제하는 함수 (is_deleted 플래그 사용) ▼▼▼
async def delete_comment(db: AsyncClient, comment_id: int):
    # 실제 삭제 대신 is_deleted: True로 업데이트 (Supabase 테이블에 is_deleted 컬럼 추가 필요)
    # response = await db.table("comments").update({"is_deleted": True}).eq("id", comment_id).execute()
    # 만약 테이블에 is_deleted 컬럼이 없다면, 아래의 물리적 삭제 코드를 사용하세요.
    response = await db.table("comments").delete().eq("id", comment_id).execute()
    return response.data

# ====== 신고 (Report) ======
async def create_report(db: AsyncClient, report: community_model.ReportCreate, user_id: str):
    report_data = report.model_dump()
    report_data['user_id'] = user_id
    response = await db.table("reports").insert(report_data).execute()
    return response.data[0] if response.data else None

async def get_all_reports(db: AsyncClient):
    response = await db.table("reports").select("*").execute()
    return response.data
