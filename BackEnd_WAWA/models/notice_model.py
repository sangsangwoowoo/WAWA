from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class NoticeBase(BaseModel):
    title: str
    content: str

class NoticeCreate(NoticeBase):
    pass

class NoticeUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None

class NoticeResponse(NoticeBase):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True