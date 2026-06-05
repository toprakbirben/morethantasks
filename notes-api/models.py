from pydantic import BaseModel
from typing import Optional


class LoginRequest(BaseModel):
    email: str
    password: str


class Note(BaseModel):
    note_id: Optional[str] = None
    title: str
    body: str
    parent_id: str | None = None
    user_id: int
    color: str | None = "#28A745"
    tag: Optional[str] = None
    last_updated: Optional[float] = None


class NoteUpdate(BaseModel):
    title: Optional[str] = None
    body: Optional[str] = None
    color: Optional[str] = None
    parent_id: Optional[str] = None
    tag: Optional[str] = None
