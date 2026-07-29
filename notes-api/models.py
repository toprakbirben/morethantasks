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
    # body is intentionally absent: once a note has a body CRDT, body is
    # written only via POST /notes/{id}/crdt_ops (see Section 3 of the design
    # spec) so the whole-note LWW path here can't clobber concurrent edits.
    title: Optional[str] = None
    color: Optional[str] = None
    parent_id: Optional[str] = None
    tag: Optional[str] = None


class CRDTOp(BaseModel):
    op_type: str  # "insert" | "delete"
    char: Optional[str] = None
    after_lamport: Optional[int] = None
    after_site_id: Optional[str] = None
    lamport: int
    site_id: str


class CRDTOpsBatch(BaseModel):
    requester_id: int
    ops: list[CRDTOp]
    # Materialized text snapshot after applying `ops` locally, written into
    # notes.body as a display/search cache (never authoritative).
    materialized_body: str


class InviteRequest(BaseModel):
    requester_id: int
    email: str


class InviteResponse(BaseModel):
    requester_id: int
    accept: bool


class TagInviteRequest(BaseModel):
    requester_id: int
    tag_name: str
    email: str


class TagRenameRequest(BaseModel):
    requester_id: int
    name: str
