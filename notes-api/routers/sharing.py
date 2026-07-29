from fastapi import APIRouter, HTTPException

from db import get_conn
from models import InviteRequest, InviteResponse

router = APIRouter()


@router.post("/notes/{note_id}/invite", status_code=201)
def invite_collaborator(note_id: str, req: InviteRequest):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute("SELECT user_id FROM notes WHERE id = %s", (note_id,))
        note = cur.fetchone()
        if note is None:
            raise HTTPException(status_code=404, detail="Note not found")
        if note[0] != req.requester_id:
            raise HTTPException(status_code=403, detail="Only the owner can invite collaborators")

        cur.execute("SELECT id FROM users WHERE email = %s", (req.email,))
        invitee = cur.fetchone()
        if invitee is None:
            # v1 shares only with existing accounts (no email-to-signup).
            raise HTTPException(status_code=404, detail="No account found for that email")
        invitee_id = invitee[0]

        if invitee_id == req.requester_id:
            raise HTTPException(status_code=400, detail="You already own this note")

        # 'pending' until the invitee accepts (see /notes/{id}/invites/respond).
        # A prior 'accepted' or 'pending' row is left as-is (idempotent resend);
        # a declined invite was deleted, so this re-creates it as 'pending'.
        cur.execute(
            """
            INSERT INTO note_collaborators (note_id, user_id, status)
            VALUES (%s, %s, 'pending')
            ON CONFLICT (note_id, user_id) DO NOTHING
            """,
            (note_id, invitee_id)
        )
    conn.commit()
    return {"status": "success", "message": "Invite sent"}


@router.get("/notes/{note_id}/collaborators")
def list_collaborators(note_id: str):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT users.id, users.email, note_collaborators.status
            FROM note_collaborators
            JOIN users ON users.id = note_collaborators.user_id
            WHERE note_collaborators.note_id = %s
            ORDER BY note_collaborators.added_at ASC
            """,
            (note_id,)
        )
        rows = cur.fetchall()
    return {"collaborators": [{"id": r[0], "email": r[1], "status": r[2]} for r in rows]}


@router.get("/users/{user_id}/invites")
def list_pending_invites(user_id: int):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT notes.id, notes.title, owners.email
            FROM note_collaborators
            JOIN notes ON notes.id = note_collaborators.note_id
            JOIN users owners ON owners.id = notes.user_id
            WHERE note_collaborators.user_id = %s AND note_collaborators.status = 'pending'
            ORDER BY note_collaborators.added_at ASC
            """,
            (user_id,)
        )
        rows = cur.fetchall()
    return {"invites": [{"note_id": r[0], "note_title": r[1], "owner_email": r[2]} for r in rows]}


@router.post("/notes/{note_id}/invites/respond")
def respond_to_invite(note_id: str, req: InviteResponse):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT 1 FROM note_collaborators WHERE note_id = %s AND user_id = %s AND status = 'pending'",
            (note_id, req.requester_id)
        )
        if cur.fetchone() is None:
            raise HTTPException(status_code=404, detail="No pending invite for this note")

        if req.accept:
            cur.execute(
                "UPDATE note_collaborators SET status = 'accepted' WHERE note_id = %s AND user_id = %s",
                (note_id, req.requester_id)
            )
        else:
            cur.execute(
                "DELETE FROM note_collaborators WHERE note_id = %s AND user_id = %s",
                (note_id, req.requester_id)
            )
    conn.commit()
    return {"status": "success"}
