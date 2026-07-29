import uuid

from fastapi import APIRouter, HTTPException

from db import get_conn
from models import CRDTOpsBatch

router = APIRouter()


def _is_authorized(cur, note_id: str, requester_id: int) -> bool:
    # Owner or collaborator, per Section 4 "CRDT endpoint authorization".
    cur.execute("SELECT user_id FROM notes WHERE id = %s", (note_id,))
    row = cur.fetchone()
    if row is None:
        return False
    if row[0] == requester_id:
        return True
    cur.execute(
        "SELECT 1 FROM note_collaborators WHERE note_id = %s AND user_id = %s AND status = 'accepted'",
        (note_id, requester_id)
    )
    if cur.fetchone() is not None:
        return True

    # Tag-sharing grants access to a shared root note's whole subtree, even
    # though only the root note itself carries a tag_id (children clear
    # theirs on reparent -- see NotesViewModel.promote in the client).
    cur.execute(
        """
        WITH RECURSIVE ancestors AS (
            SELECT id, parent_id, tag_id FROM notes WHERE id = %s
            UNION ALL
            SELECT n.id, n.parent_id, n.tag_id
            FROM notes n JOIN ancestors a ON n.id = a.parent_id
        )
        SELECT 1 FROM ancestors a
        JOIN tag_collaborators tc ON tc.tag_id = a.tag_id
        WHERE tc.user_id = %s AND tc.status = 'accepted'
        LIMIT 1
        """,
        (note_id, requester_id)
    )
    return cur.fetchone() is not None


@router.post("/notes/{note_id}/crdt_ops", status_code=201)
def append_crdt_ops(note_id: str, batch: CRDTOpsBatch):
    conn = get_conn()
    with conn.cursor() as cur:
        if not _is_authorized(cur, note_id, batch.requester_id):
            raise HTTPException(status_code=403, detail="Not the owner or a collaborator on this note")

        for op in batch.ops:
            if op.op_type not in ("insert", "delete"):
                raise HTTPException(status_code=400, detail=f"Invalid op_type: {op.op_type}")
            try:
                site_uuid = uuid.UUID(op.site_id)
                after_site_uuid = uuid.UUID(op.after_site_id) if op.after_site_id else None
            except ValueError:
                raise HTTPException(status_code=400, detail="site_id/after_site_id must be valid UUIDs")

            # PK (note_id, lamport, site_id) makes retries/duplicates idempotent.
            cur.execute(
                """
                INSERT INTO note_crdt_ops
                    (note_id, op_type, char, after_lamport, after_site_id, lamport, site_id)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (note_id, lamport, site_id) DO NOTHING
                """,
                (note_id, op.op_type, op.char, op.after_lamport, after_site_uuid,
                 op.lamport, site_uuid)
            )

        # body cache: display/search only, never authoritative — the op log is truth.
        cur.execute(
            "UPDATE notes SET body = %s, last_updated = now() WHERE id = %s",
            (batch.materialized_body, note_id)
        )
    conn.commit()
    return {"status": "success"}


@router.get("/notes/{note_id}/crdt_ops")
def fetch_crdt_ops(note_id: str, requester_id: int, since: int = 0):
    conn = get_conn()
    with conn.cursor() as cur:
        if not _is_authorized(cur, note_id, requester_id):
            raise HTTPException(status_code=403, detail="Not the owner or a collaborator on this note")

        cur.execute(
            """
            SELECT op_type, char, after_lamport, after_site_id, lamport, site_id, server_seq
            FROM note_crdt_ops
            WHERE note_id = %s AND server_seq > %s
            ORDER BY server_seq ASC
            """,
            (note_id, since)
        )
        rows = cur.fetchall()

    ops = [
        {
            "op_type": r[0],
            "char": r[1],
            "after_lamport": r[2],
            "after_site_id": str(r[3]) if r[3] else None,
            "lamport": r[4],
            "site_id": str(r[5]),
        }
        for r in rows
    ]
    latest_seq = rows[-1][6] if rows else since
    return {"ops": ops, "latest_seq": latest_seq}
