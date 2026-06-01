from fastapi import FastAPI

from db import ensure_sync_schema
from routers import notes, users

app = FastAPI()

ensure_sync_schema()

app.include_router(users.router)
app.include_router(notes.router)

# uvicorn main:app --reload --host 0.0.0.0 --port 8000
