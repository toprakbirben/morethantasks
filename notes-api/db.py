import os

import psycopg2

# Single source of truth for the DB host. The server reaches Postgres through
# the SSH tunnel on localhost:5432; override with NOTES_DB_HOST if it moves.
DB_HOST = os.getenv("NOTES_DB_HOST", "127.0.0.1")

_conn = None


def get_conn():
    # Connect lazily (and reopen if the connection was closed) so the API
    # process can start even when Postgres is briefly unreachable. The failure
    # then surfaces per-request instead of crashing uvicorn at import time.
    global _conn
    if _conn is None or _conn.closed:
        _conn = psycopg2.connect(
            host=DB_HOST,
            database="notes",
            user="notes",
            password="notes"
        )
    return _conn
