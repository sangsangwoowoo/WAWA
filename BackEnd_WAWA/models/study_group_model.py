from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime

# 그룹 생성 요청
class StudyGroupCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=100)
    description: Optional[str] = Field(None, max_length=500)
    max_members: int = Field(default=10, ge=2, le=50)
    requires_approval: bool = Field(default=False)

# 그룹 응답
class StudyGroupResponse(BaseModel):
    id: int
    name: str
    description: Optional[str]
    created_by: str
    creator_name: Optional[str]
    max_members: int
    member_count: int
    is_member: bool
    is_owner: bool
    requires_approval: bool
    created_at: datetime

# 그룹 멤버 응답
class GroupMemberResponse(BaseModel):
    user_id: str
    user_name: str
    role: str
    joined_at: datetime

class GroupMessageCreate(BaseModel):
    content: str = Field(..., min_length=1)

class GroupMessageResponse(BaseModel):
    id: int
    group_id: int
    user_id: str
    user_name: str
    content: str
    created_at: datetime

class JoinRequestResponse(BaseModel):
    request_id: int
    user_id: str
    user_name: str
    requested_at: datetime