from fastapi import FastAPI

from migrate import run_migrations
from routers import crdt, notes, sharing, tags, users

app = FastAPI()

try:
    run_migrations()
except Exception as e:
    # Don't let a transient DB outage block startup; migrations are tracked and
    # any un-applied ones will run on the next boot once Postgres is reachable.
    print("Skipping migrations, database unreachable:", e)

app.include_router(users.router)
app.include_router(notes.router)
app.include_router(crdt.router)
app.include_router(sharing.router)
app.include_router(tags.router)

# uvicorn main:app --reload --host 0.0.0.0 --port 8000
