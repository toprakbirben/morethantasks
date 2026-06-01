from datetime import datetime
import uuid

from fastapi import APIRouter

from db import conn
from models import Note, NoteUpdate, DeleteNoteRequest

router = APIRouter()


@router.post("/add_note")
def add_note(note: Note):
    # Client-generated id is canonical across SQLite and Postgres. ON CONFLICT
    # makes outbox retries idempotent. parent_id/color arrive as "" → store NULL;
    # last_updated is epoch seconds from the device.
    note_id = note.note_id or str(uuid.uuid4())
    last_updated = note.last_updated if note.last_updated is not None else datetime.now().timestamp()
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO notes (id, title, body, parent_id, last_updated, user_id, color, tag, deleted)
            VALUES (%s, %s, %s, NULLIF(%s, ''), to_timestamp(%s), %s, NULLIF(%s, ''), %s, false)
            ON CONFLICT (id) DO NOTHING
            """,
            (note_id, note.title, note.body, note.parent_id, last_updated,
             note.user_id, note.color, note.tag)
        )
    conn.commit()
    return {"status": "success", "message": "Note added", "note_id": note_id}


@router.delete("/remove_note")
def remove_note(request: DeleteNoteRequest):
    # Soft delete (tombstone) so other devices learn of the deletion on pull.
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE notes SET deleted = true, last_updated = now() WHERE id = %s",
            (request.note_id,)
        )
    conn.commit()
    return {"status": "success", "message": "Note removed"}


@router.patch("/edit_note")
def edit_note(note: NoteUpdate):
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE notes
            SET title = COALESCE(%s, title),
                body = COALESCE(%s, body),
                color = COALESCE(%s, color),
                parent_id = COALESCE(%s, parent_id),
                tag = COALESCE(%s, tag),
                deleted = false,
                last_updated = %s
            WHERE id = %s
            """,
            (note.title, note.body, note.color, note.parent_id, note.tag, datetime.now(), note.note_id)
        )
    conn.commit()
    return {"status": "success", "message": "Note updated"}
