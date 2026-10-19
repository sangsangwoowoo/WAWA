# models/community_model.py

from pydantic import BaseModel, ConfigDict
from typing import Optional
from datetime import datetime

# ====== 게시글 (Post) ======
class PostBase(BaseModel):
    title: str
    content: str
    category: str

class PostCreate(PostBase):
    pass

class PostUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None

class AuthorInfo(BaseModel):
    name: str
    model_config = ConfigDict(from_attributes=True)

class PostResponse(PostBase):
    id: int
    user_id: str
    created_at: datetime
    is_deleted: bool
    user_account: AuthorInfo
    model_config = ConfigDict(from_attributes=True)

# ====== 댓글 (Comment) ======
class CommentBase(BaseModel):
    content: str

class CommentCreate(CommentBase):
    pass

# ▼▼▼ [신규] 댓글 수정을 위한 모델 추가 ▼▼▼
class CommentUpdate(BaseModel):
    content: str

class CommentResponse(CommentBase):
    id: int
    user_id: str
    post_id: int
    created_at: datetime
    user_account: AuthorInfo
    model_config = ConfigDict(from_attributes=True)

# ====== 신고 (Report) ======
class ReportBase(BaseModel):
    reason: str
    post_id: Optional[int] = None
    comment_id: Optional[int] = None

class ReportCreate(ReportBase):
    pass

class ReportResponse(ReportBase):
    id: int
    user_id: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)
