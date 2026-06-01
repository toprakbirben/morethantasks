import psycopg2

_conn = None


def get_conn():
    # Connect lazily (and reopen if the connection was closed) so the API
    # process can start even when Postgres is briefly unreachable. The failure
    # then surfaces per-request instead of crashing uvicorn at import time.
    global _conn
    if _conn is None or _conn.closed:
        _conn = psycopg2.connect(
            host="192.168.178.187",
            database="notes",
            user="notes",
            password="notes"
        )
    return _conn


def ensure_sync_schema():
    # Idempotent migration for the sync rewrite: tombstone flag + timestamp,
    # and a unique id so add_note's ON CONFLICT (id) works. `deleted` is added
    # last so the client's positional pull read keeps the expected column order.
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute("ALTER TABLE notes ADD COLUMN IF NOT EXISTS last_updated TIMESTAMP NOT NULL DEFAULT now();")
        cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS notes_id_key ON notes (id);")
        cur.execute("ALTER TABLE notes ADD COLUMN IF NOT EXISTS deleted BOOLEAN NOT NULL DEFAULT false;")
    conn.commit()
