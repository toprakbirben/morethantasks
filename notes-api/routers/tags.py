import uuid

from fastapi import APIRouter, HTTPException

from db import get_conn
from models import InviteResponse, TagInviteRequest, TagRenameRequest

router = APIRouter()


def get_or_create_tag(cur, owner_id: int, name: str) -> str:
    # Tags are get-or-create by (owner_id, name) so note create/update can
    # keep sending a plain tag name -- the client never has to know a tag_id
    # exists until it wants to share or rename the tag.
    cur.execute("SELECT id FROM tags WHERE owner_id = %s AND name = %s", (owner_id, name))
    row = cur.fetchone()
    if row is not None:
        return row[0]
    tag_id = str(uuid.uuid4())
    cur.execute(
        "INSERT INTO tags (id, owner_id, name) VALUES (%s, %s, %s)",
        (tag_id, owner_id, name)
    )
    return tag_id


@router.post("/tags/invite", status_code=201)
def invite_to_tag(req: TagInviteRequest):
    conn = get_conn()
    with conn.cursor() as cur:
        tag_id = get_or_create_tag(cur, req.requester_id, req.tag_name)

        cur.execute("SELECT id FROM users WHERE email = %s", (req.email,))
        invitee = cur.fetchone()
        if invitee is None:
            # v1 shares only with existing accounts (no email-to-signup).
            raise HTTPException(status_code=404, detail="No account found for that email")
        invitee_id = invitee[0]

        if invitee_id == req.requester_id:
            raise HTTPException(status_code=400, detail="You already own this tag")

        # 'pending' until the invitee accepts; idempotent resend if already
        # pending/accepted, re-created as 'pending' if a decline deleted it.
        cur.execute(
            """
            INSERT INTO tag_collaborators (tag_id, user_id, status)
            VALUES (%s, %s, 'pending')
            ON CONFLICT (tag_id, user_id) DO NOTHING
            """,
            (tag_id, invitee_id)
        )
    conn.commit()
    return {"status": "success", "message": "Invite sent"}


@router.get("/users/{user_id}/tags/{name}/collaborators")
def list_tag_collaborators(user_id: int, name: str):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute("SELECT id FROM tags WHERE owner_id = %s AND name = %s", (user_id, name))
        tag = cur.fetchone()
        if tag is None:
            return {"collaborators": []}
        cur.execute(
            """
            SELECT users.id, users.email, tag_collaborators.status
            FROM tag_collaborators
            JOIN users ON users.id = tag_collaborators.user_id
            WHERE tag_collaborators.tag_id = %s
            ORDER BY tag_collaborators.added_at ASC
            """,
            (tag[0],)
        )
        rows = cur.fetchall()
    return {"collaborators": [{"id": r[0], "email": r[1], "status": r[2]} for r in rows]}


@router.get("/users/{user_id}/tag-invites")
def list_pending_tag_invites(user_id: int):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT tags.id, tags.name, owners.email
            FROM tag_collaborators
            JOIN tags ON tags.id = tag_collaborators.tag_id
            JOIN users owners ON owners.id = tags.owner_id
            WHERE tag_collaborators.user_id = %s AND tag_collaborators.status = 'pending'
            ORDER BY tag_collaborators.added_at ASC
            """,
            (user_id,)
        )
        rows = cur.fetchall()
    return {"invites": [{"tag_id": r[0], "tag_name": r[1], "owner_email": r[2]} for r in rows]}


@router.post("/tags/{tag_id}/invites/respond")
def respond_to_tag_invite(tag_id: str, req: InviteResponse):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT 1 FROM tag_collaborators WHERE tag_id = %s AND user_id = %s AND status = 'pending'",
            (tag_id, req.requester_id)
        )
        if cur.fetchone() is None:
            raise HTTPException(status_code=404, detail="No pending invite for this tag")

        if req.accept:
            cur.execute(
                "UPDATE tag_collaborators SET status = 'accepted' WHERE tag_id = %s AND user_id = %s",
                (tag_id, req.requester_id)
            )
        else:
            cur.execute(
                "DELETE FROM tag_collaborators WHERE tag_id = %s AND user_id = %s",
                (tag_id, req.requester_id)
            )
    conn.commit()
    return {"status": "success"}


@router.get("/tags/shared-with-me")
def list_shared_tags(user_id: int):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT tags.id, tags.name, owners.email
            FROM tag_collaborators
            JOIN tags ON tags.id = tag_collaborators.tag_id
            JOIN users owners ON owners.id = tags.owner_id
            WHERE tag_collaborators.user_id = %s AND tag_collaborators.status = 'accepted'
            ORDER BY tags.name ASC
            """,
            (user_id,)
        )
        rows = cur.fetchall()
    return {"tags": [{"id": r[0], "name": r[1], "owner_email": r[2]} for r in rows]}


@router.get("/tags/{tag_id}/notes")
def list_notes_for_tag(tag_id: str, requester_id: int):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute("SELECT owner_id FROM tags WHERE id = %s", (tag_id,))
        tag = cur.fetchone()
        if tag is None:
            raise HTTPException(status_code=404, detail="Tag not found")

        if tag[0] != requester_id:
            cur.execute(
                "SELECT 1 FROM tag_collaborators WHERE tag_id = %s AND user_id = %s AND status = 'accepted'",
                (tag_id, requester_id)
            )
            if cur.fetchone() is None:
                raise HTTPException(status_code=403, detail="Not the owner or a collaborator on this tag")

        # A tag only ever labels its root note(s); the whole "tagged place"
        # includes everything nested underneath, walked via parent_id.
        cur.execute(
            """
            WITH RECURSIVE tree AS (
                SELECT id FROM notes WHERE tag_id = %s AND deleted = false
                UNION ALL
                SELECT n.id FROM notes n JOIN tree t ON n.parent_id = t.id WHERE n.deleted = false
            )
            SELECT notes.id, notes.title, notes.body, notes.parent_id, notes.last_updated,
                   notes.user_id, notes.color, tags.name, notes.deleted
            FROM notes
            LEFT JOIN tags ON tags.id = notes.tag_id
            JOIN tree ON tree.id = notes.id
            """,
            (tag_id,)
        )
        rows = cur.fetchall()

    return {"notes": [
        {
            "id": r[0], "title": r[1], "body": r[2], "parent_id": r[3],
            "last_updated": r[4].timestamp() if r[4] else None,
            "user_id": r[5], "color": r[6], "tag": r[7], "deleted": r[8],
        }
        for r in rows
    ]}


@router.patch("/users/{user_id}/tags/{name}")
def rename_tag(user_id: int, name: str, req: TagRenameRequest):
    # By (owner, current name) rather than tag_id -- the client never needs
    # to know a tag_id exists to invite, list, or rename its own tags.
    if req.requester_id != user_id:
        raise HTTPException(status_code=403, detail="Only the owner can rename this tag")
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute("SELECT id FROM tags WHERE owner_id = %s AND name = %s", (user_id, name))
        row = cur.fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Tag not found")
        cur.execute("UPDATE tags SET name = %s WHERE id = %s", (req.name, row[0]))
    conn.commit()
    return {"status": "success"}
