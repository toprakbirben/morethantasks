from fastapi import FastAPI

from db import ensure_sync_schema
from routers import notes, users

app = FastAPI()

try:
    ensure_sync_schema()
except Exception as e:
    # Don't let a transient DB outage block startup; the migration is
    # idempotent and will run on the next boot once Postgres is reachable.
    print("Skipping schema migration, database unreachable:", e)

app.include_router(users.router)
app.include_router(notes.router)

# uvicorn main:app --reload --host 0.0.0.0 --port 8000
