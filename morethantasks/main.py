from fastapi import FastAPI
from pydantic import BaseModel
from datetime import datetime
from typing import Optional
import psycopg2
import uuid

app = FastAPI()

class Note(BaseModel):
    title: str
    body: str
    parent_id: str | None = None
    created_by_user_id: str
    color: str | None = "#28A745"  
    tag: Optional[str] = None 


class NoteUpdate(BaseModel):
    note_id: str
    title: Optional[str] = None
    body: Optional[str] = None
    color: Optional[str] = None
    parent_id: Optional[str] = None
    tag: Optional[str] = None

class DeleteNoteRequest(BaseModel):
    note_id: str
    
conn = psycopg2.connect(
    host="192.168.178.187",
    database="notes",
    user="notes",
    password="notes"
)


@app.post("/add_note")
def add_note(note: Note):
    note_id = str(uuid.uuid4())
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO notes (id, title, body, parent_id, last_updated, created_by_user_id, color, tag)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (note_id, note.title, note.body, note.parent_id, datetime.now(),
             note.created_by_user_id, note.color, note.tag)
        )
    conn.commit()
    return {"status": "success", "message": "Note added", "note_id": note_id}

@app.delete("/remove_note")
def remove_note(request: DeleteNoteRequest):
    cur = conn.cursor()
    cur.execute("DELETE FROM notes WHERE id = %s", (request.note_id,))
    conn.commit()
    cur.close()
    return {"status": "success", "message": "Note removed"}


@app.patch("/edit_note")
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
                last_updated = %s
            WHERE id = %s
            """,
            (note.title, note.body, note.color, note.parent_id, note.tag, datetime.now(), note.note_id)
        )
    conn.commit()
    return {"status": "success", "message": "Note updated"}


# uvicorn main:app --reload --host 0.0.0.0 --port 8000