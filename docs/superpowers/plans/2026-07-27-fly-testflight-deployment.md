# Fly.io + TestFlight Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `notes-api` from a LAN-only FastAPI+Postgres setup to a publicly reachable Fly.io deployment, and get `morethantasks` onto TestFlight — safely, given the GitHub repo (`toprakbirben/morethantasks`) is public.

**Architecture:** Fly.io hosts the FastAPI app in a container; Fly Postgres is attached over Fly's private network only (never publicly reachable, never embeds credentials in the client). The iOS app authenticates with a bearer token issued at login; every notes/account endpoint derives `user_id` from that verified token instead of trusting a client-supplied value. The client's only remaining direct-Postgres code path (`fetchNotesForSync`) is replaced with an authenticated HTTP call, matching how insert/update/delete already work.

**Tech Stack:** FastAPI, psycopg2, Fly.io (Fly Postgres, `fly.toml`, Docker), Swift/SwiftUI, Keychain Services, Swift Testing, pytest.

## Global Constraints

- Repo is public (`github.com/toprakbirben/morethantasks`) — no secret, password, or production credential may be committed. Fly secrets and Xcode signing/App Store Connect are the only places credentials live.
- No token expiry/revocation endpoint in this plan (YAGNI — the vulnerability being closed is *unverified client-supplied user_id*, not *token lifetime*; revocation can be a later follow-up).
- Match existing patterns: idempotent delete stays idempotent (404/mismatch cases still return 204, matching current retry-safe behavior), lazy DB connection pattern in `db.py` is preserved, Swift Testing + `MockURLProtocol` conventions in `morethantasksTests` are reused, not replaced.
- Local dev must keep working with no Fly account: `db.py` still defaults to `127.0.0.1`/`notes`/`notes` when `DATABASE_URL` isn't set.

---

## File Structure

**Backend (`notes-api/`):**
- `migrations/004_auth_tokens.sql` — new: `auth_tokens` table
- `auth.py` — new: token generation + `get_current_user_id` FastAPI dependency
- `db.py` — modify: read `DATABASE_URL` (Fly) or discrete env vars (local), no hardcoded prod credential
- `models.py` — modify: drop client-supplied `user_id` from `Note`
- `routers/notes.py` — modify: add `GET /notes`, require the auth dependency on all four routes, scope UPDATE/DELETE by `user_id`
- `routers/users.py` — modify: issue a token on login, delete tokens before deleting a user, require auth on account deletion
- `main.py` — modify: add `/health` endpoint
- `Dockerfile` — new
- `fly.toml` — new
- `.gitignore` — new: ignore `.env`
- `tests/test_auth.py`, `tests/test_notes.py` — new: pytest coverage for the auth gate

**iOS (`morethantasks/`):**
- `Persistence/Keychain.swift` — new: minimal get/set/delete wrapper around Keychain Services
- `Persistence/AuthService.swift` — modify: store/attach/clear the bearer token
- `Persistence/PostgresDatabase.swift` — modify: drop `PostgresClientKit`, `fetchNotesForSync` becomes an authenticated HTTP call like the other three methods
- `Persistence/ServerConfig.swift` — modify: point at the Fly `https://` URL
- `Sync/SyncEngine.swift` — modify: `fetchRemote` no longer needs the blocking-thread workaround
- `morethantasksTests/AuthTests.swift` — modify: cover token storage
- Xcode project — manual: remove the `PostgresClientKit` Swift Package dependency, bump build number for TestFlight

---

### Task 1: Backend — DB config from environment only

**Files:**
- Modify: `notes-api/db.py`

**Interfaces:**
- Produces: `get_conn() -> psycopg2.connection` (unchanged signature, callers in `routers/*.py` and `migrate.py` are untouched)

- [ ] **Step 1: Rewrite `db.py` to prefer `DATABASE_URL`, fall back to discrete local env vars**

```python
import os

import psycopg2

_conn = None


def get_conn():
    # Connect lazily (and reopen if the connection was closed) so the API
    # process can start even when Postgres is briefly unreachable. The failure
    # then surfaces per-request instead of crashing uvicorn at import time.
    #
    # DATABASE_URL is set by `fly postgres attach` as a Fly secret in
    # production; it's never present locally, so local dev keeps using the
    # discrete NOTES_DB_* vars (defaulting to the local dev Postgres).
    global _conn
    if _conn is None or _conn.closed:
        database_url = os.getenv("DATABASE_URL")
        if database_url:
            _conn = psycopg2.connect(database_url)
        else:
            _conn = psycopg2.connect(
                host=os.getenv("NOTES_DB_HOST", "127.0.0.1"),
                database=os.getenv("NOTES_DB_NAME", "notes"),
                user=os.getenv("NOTES_DB_USER", "notes"),
                password=os.getenv("NOTES_DB_PASSWORD", "notes"),
            )
    return _conn
```

- [ ] **Step 2: Verify local dev still boots**

Run: `cd notes-api && uvicorn main:app --reload --host 0.0.0.0 --port 8000`
Expected: starts and logs migrations against your local Postgres exactly as before (no env vars needed locally).

- [ ] **Step 3: Commit**

```bash
git add notes-api/db.py
git commit -m "Read DB connection from env vars, defaulting to local dev Postgres"
```

---

### Task 2: Backend — auth tokens (migration + issuance + verification)

**Files:**
- Create: `notes-api/migrations/004_auth_tokens.sql`
- Create: `notes-api/auth.py`
- Modify: `notes-api/routers/users.py`
- Test: `notes-api/tests/test_auth.py`

**Interfaces:**
- Produces: `auth.generate_token() -> str`, `auth.get_current_user_id(authorization: str | None) -> int` (raises `HTTPException(401)`), both consumed by `routers/notes.py` in Task 3.

- [ ] **Step 1: Add the migration**

```sql
-- 004_auth_tokens.sql
-- Opaque bearer tokens issued at login. Every notes/account request now
-- resolves user_id from a verified token instead of trusting whatever
-- user_id the client puts in the request body — required once the API is
-- reachable from the public internet instead of just the LAN.

CREATE TABLE auth_tokens (
    token      text NOT NULL PRIMARY KEY,
    user_id    integer NOT NULL REFERENCES users(id),
    created_at timestamp NOT NULL DEFAULT now()
);

CREATE INDEX idx_auth_tokens_user_id ON auth_tokens (user_id);
```

- [ ] **Step 2: Write the failing test for the verification dependency**

```python
# notes-api/tests/test_auth.py
from unittest.mock import MagicMock, patch

from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

from auth import get_current_user_id

app = FastAPI()


@app.get("/whoami")
def whoami(user_id: int = Depends(get_current_user_id)):
    return {"user_id": user_id}


client = TestClient(app)


def _mock_conn(fetchone_result):
    cursor = MagicMock()
    cursor.fetchone.return_value = fetchone_result
    cursor.__enter__.return_value = cursor
    conn = MagicMock()
    conn.cursor.return_value = cursor
    return conn


def test_missing_authorization_header_returns_401():
    response = client.get("/whoami")
    assert response.status_code == 401


def test_malformed_authorization_header_returns_401():
    response = client.get("/whoami", headers={"Authorization": "Token abc"})
    assert response.status_code == 401


@patch("auth.get_conn")
def test_unknown_token_returns_401(mock_get_conn):
    mock_get_conn.return_value = _mock_conn(fetchone_result=None)
    response = client.get("/whoami", headers={"Authorization": "Bearer bogus"})
    assert response.status_code == 401


@patch("auth.get_conn")
def test_valid_token_resolves_user_id(mock_get_conn):
    mock_get_conn.return_value = _mock_conn(fetchone_result=(42,))
    response = client.get("/whoami", headers={"Authorization": "Bearer good-token"})
    assert response.status_code == 200
    assert response.json() == {"user_id": 42}
```

- [ ] **Step 3: Run it to verify it fails (module doesn't exist yet)**

Run: `cd notes-api && python -m pytest tests/test_auth.py -v`
Expected: FAIL / ERROR — `ModuleNotFoundError: No module named 'auth'`

- [ ] **Step 4: Implement `auth.py`**

```python
# notes-api/auth.py
import secrets

from fastapi import Header, HTTPException

from db import get_conn


def generate_token() -> str:
    return secrets.token_urlsafe(32)


def get_current_user_id(authorization: str | None = Header(default=None)) -> int:
    if authorization is None or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or malformed bearer token")

    token = authorization.removeprefix("Bearer ")
    conn = get_conn()
    conn.rollback()
    with conn.cursor() as cur:
        cur.execute("SELECT user_id FROM auth_tokens WHERE token = %s", (token,))
        result = cur.fetchone()

    if result is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return result[0]
```

- [ ] **Step 5: Run the test again**

Run: `cd notes-api && python -m pytest tests/test_auth.py -v`
Expected: PASS (4 tests)

- [ ] **Step 6: Issue a token on login, in `routers/users.py`**

Modify `create_session` (the `POST /sessions` handler) and its helper:

```python
from fastapi import APIRouter, HTTPException

from auth import generate_token
from db import get_conn
from models import LoginRequest

router = APIRouter()


@router.post("/sessions")
async def create_session(request: LoginRequest):
    user = await login_user(request.email, request.password)
    if user:
        token = generate_token()
        conn = get_conn()
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO auth_tokens (token, user_id) VALUES (%s, %s)",
                (token, user["id"]),
            )
        conn.commit()
        return {
            "user": {
                "id": user["id"],
                "email": user["email"]
            },
            "token": token
        }
    raise HTTPException(status_code=401, detail="Invalid email or password")
```

- [ ] **Step 7: Delete a user's tokens before deleting the user, and require auth on account deletion**

```python
@router.delete("/users/{user_id}", status_code=204)
def delete_user(user_id: int, authenticated_user_id: int = Depends(get_current_user_id)):
    if authenticated_user_id != user_id:
        raise HTTPException(status_code=403, detail="Cannot delete another user's account")
    conn = get_conn()
    try:
        with conn.cursor() as curr:
            # Delete dependents first to respect FK constraints.
            curr.execute("DELETE FROM auth_tokens WHERE user_id = %s", (user_id,))
            curr.execute("DELETE FROM notes WHERE user_id = %s", (user_id,))
            curr.execute("DELETE FROM users WHERE id = %s", (user_id,))
        conn.commit()
        return None
    except Exception as e:
        conn.rollback()
        print("Delete user error:", e)
        raise HTTPException(status_code=500, detail="Could not delete user")
```

Add `Depends` to the existing `from fastapi import ...` import line at the top of the file.

- [ ] **Step 8: Run the full backend test suite**

Run: `cd notes-api && python -m pytest -v`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add notes-api/migrations/004_auth_tokens.sql notes-api/auth.py notes-api/routers/users.py notes-api/tests/test_auth.py
git commit -m "Issue bearer tokens on login and require them for account deletion"
```

---

### Task 3: Backend — protect notes endpoints, add GET /notes

**Files:**
- Modify: `notes-api/routers/notes.py`
- Modify: `notes-api/models.py`
- Test: `notes-api/tests/test_notes.py`

**Interfaces:**
- Consumes: `auth.get_current_user_id` from Task 2.
- Produces: `GET /notes` response shape `[{note_id, title, body, parent_id, last_updated, color, tag, deleted}]`, consumed by the iOS client in Task 7.

- [ ] **Step 1: Write the failing tests**

```python
# notes-api/tests/test_notes.py
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from auth import get_current_user_id
from main import app

client = TestClient(app)


def _mock_conn(rowcount=1, fetchall_result=None):
    cursor = MagicMock()
    cursor.rowcount = rowcount
    cursor.fetchall.return_value = fetchall_result or []
    cursor.__enter__.return_value = cursor
    conn = MagicMock()
    conn.cursor.return_value = cursor
    return conn, cursor


def test_get_notes_requires_auth():
    response = client.get("/notes")
    assert response.status_code == 401


def test_get_notes_scopes_query_to_authenticated_user():
    app.dependency_overrides[get_current_user_id] = lambda: 7
    try:
        conn, cursor = _mock_conn()
        with patch("routers.notes.get_conn", return_value=conn):
            response = client.get("/notes")
            assert response.status_code == 200
            params = cursor.execute.call_args.args[1]
            assert 7 in params
    finally:
        app.dependency_overrides.clear()


def test_delete_note_scopes_query_to_authenticated_user():
    app.dependency_overrides[get_current_user_id] = lambda: 7
    try:
        conn, cursor = _mock_conn()
        with patch("routers.notes.get_conn", return_value=conn):
            response = client.delete("/notes/some-id")
            assert response.status_code == 204
            params = cursor.execute.call_args.args[1]
            assert params == ("some-id", 7)
    finally:
        app.dependency_overrides.clear()


def test_update_note_scopes_query_to_authenticated_user():
    app.dependency_overrides[get_current_user_id] = lambda: 7
    try:
        conn, cursor = _mock_conn()
        with patch("routers.notes.get_conn", return_value=conn):
            response = client.patch("/notes/some-id", json={"title": "New"})
            assert response.status_code == 200
            params = cursor.execute.call_args.args[1]
            assert params[-2:] == ("some-id", 7)
    finally:
        app.dependency_overrides.clear()


def test_create_note_ignores_any_client_supplied_user_id_and_uses_token():
    app.dependency_overrides[get_current_user_id] = lambda: 7
    try:
        conn, cursor = _mock_conn()
        with patch("routers.notes.get_conn", return_value=conn):
            response = client.post("/notes", json={"title": "T", "body": "B"})
            assert response.status_code == 201
            params = cursor.execute.call_args.args[1]
            assert 7 in params
    finally:
        app.dependency_overrides.clear()
```

- [ ] **Step 2: Run to verify these fail**

Run: `cd notes-api && python -m pytest tests/test_notes.py -v`
Expected: FAIL (no auth required yet, `Note` still requires `user_id` in the body so `test_create_note_...` gets a 422)

- [ ] **Step 3: Drop the client-supplied `user_id` from the `Note` model, in `models.py`**

```python
class Note(BaseModel):
    note_id: Optional[str] = None
    title: str
    body: str
    parent_id: str | None = None
    color: str | None = "#28A745"
    tag: Optional[str] = None
    last_updated: Optional[float] = None
```

(Remove the `user_id: int` line.)

- [ ] **Step 4: Rewrite `routers/notes.py`**

```python
from datetime import datetime
import uuid

from fastapi import APIRouter, Depends

from auth import get_current_user_id
from db import get_conn
from models import Note, NoteUpdate

router = APIRouter()


@router.get("/notes")
def list_notes(user_id: int = Depends(get_current_user_id)):
    conn = get_conn()
    conn.rollback()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, title, body, parent_id, last_updated, color, tag, deleted "
            "FROM notes WHERE user_id = %s",
            (user_id,)
        )
        rows = cur.fetchall()

    return [
        {
            "note_id": row[0],
            "title": row[1],
            "body": row[2],
            "parent_id": row[3],
            "last_updated": row[4].timestamp(),
            "color": row[5],
            "tag": row[6],
            "deleted": row[7],
        }
        for row in rows
    ]


@router.post("/notes", status_code=201)
def create_note(note: Note, user_id: int = Depends(get_current_user_id)):
    # Client-generated id is canonical across SQLite and Postgres. ON CONFLICT
    # makes outbox retries idempotent. parent_id/color arrive as "" → store NULL;
    # last_updated is epoch seconds from the device.
    note_id = note.note_id or str(uuid.uuid4())
    last_updated = note.last_updated if note.last_updated is not None else datetime.now().timestamp()
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO notes (id, title, body, parent_id, last_updated, user_id, color, tag, deleted)
            VALUES (%s, %s, %s, NULLIF(%s, ''), to_timestamp(%s), %s, NULLIF(%s, ''), %s, false)
            ON CONFLICT (id) DO NOTHING
            """,
            (note_id, note.title, note.body, note.parent_id, last_updated,
             user_id, note.color, note.tag)
        )
    conn.commit()
    return {"status": "success", "message": "Note added", "note_id": note_id}


@router.delete("/notes/{note_id}", status_code=204)
def delete_note(note_id: str, user_id: int = Depends(get_current_user_id)):
    # Soft delete (tombstone), scoped to the authenticated user so a non-owner's
    # request silently no-ops instead of leaking whether the note exists.
    # Idempotent: deleting a missing/already-deleted/not-yours note still
    # returns 204 so the client's outbox retries don't loop forever.
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE notes SET deleted = true, last_updated = now() WHERE id = %s AND user_id = %s",
            (note_id, user_id)
        )
    conn.commit()
    return None


@router.patch("/notes/{note_id}")
def update_note(note_id: str, note: NoteUpdate, user_id: int = Depends(get_current_user_id)):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE notes
            SET title = COALESCE(%s, title),
                color = COALESCE(%s, color),
                parent_id = CASE WHEN %s IS NULL THEN parent_id ELSE NULLIF(%s, '') END,
                tag = COALESCE(%s, tag),
                deleted = false,
                last_updated = %s
            WHERE id = %s AND user_id = %s
            """,
            (note.title, note.color, note.parent_id, note.parent_id,
             note.tag, datetime.now(), note_id, user_id)
        )
    conn.commit()
    return {"status": "success", "message": "Note updated"}
```

- [ ] **Step 5: Run the tests again**

Run: `cd notes-api && python -m pytest tests/test_notes.py -v`
Expected: PASS (5 tests)

- [ ] **Step 6: Run the full backend suite**

Run: `cd notes-api && python -m pytest -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add notes-api/routers/notes.py notes-api/models.py notes-api/tests/test_notes.py
git commit -m "Require bearer auth on notes endpoints, scope writes by user, add GET /notes"
```

---

### Task 4: Backend — health check + Dockerfile

**Files:**
- Modify: `notes-api/main.py`
- Create: `notes-api/Dockerfile`
- Create: `notes-api/.dockerignore`

**Interfaces:**
- Produces: `GET /health` → `{"status": "ok"}`, used by Fly's `http_service.checks` in Task 5.

- [ ] **Step 1: Add the health endpoint to `main.py`**

```python
from fastapi import FastAPI

from migrate import run_migrations
from routers import notes, users

app = FastAPI()

try:
    run_migrations()
except Exception as e:
    # Don't let a transient DB outage block startup; migrations are tracked and
    # any un-applied ones will run on the next boot once Postgres is reachable.
    print("Skipping migrations, database unreachable:", e)

app.include_router(users.router)
app.include_router(notes.router)


@app.get("/health")
def health():
    # Deliberately doesn't touch the DB — mirrors the startup try/except above,
    # so Fly's health check doesn't flap during a brief Postgres outage.
    return {"status": "ok"}

# uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

- [ ] **Step 2: Add the Dockerfile**

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 3: Add `.dockerignore`**

```
__pycache__
*.pyc
.git
```

- [ ] **Step 4: Build the image locally to verify it works**

Run: `cd notes-api && docker build -t notes-api-test .`
Expected: builds without error.

Run: `docker run --rm -p 8000:8000 notes-api-test`, then in another shell: `curl http://127.0.0.1:8000/health`
Expected: `{"status":"ok"}` (migrations will fail to reach a DB inside the container — that's fine and matches the try/except; the health check itself must still respond).

- [ ] **Step 5: Commit**

```bash
git add notes-api/main.py notes-api/Dockerfile notes-api/.dockerignore
git commit -m "Add health endpoint and Dockerfile for Fly.io deployment"
```

---

### Task 5: Backend — Fly.io app + Postgres + secrets

**Files:**
- Create: `notes-api/fly.toml`
- Create: `.gitignore` (repo root, or `notes-api/.gitignore` if none exists at root)

**Interfaces:**
- Consumes: `Dockerfile` and `/health` from Task 4.
- Produces: a running Fly app serving `notes-api`, and the `DATABASE_URL` secret consumed by `db.py` from Task 1.

- [ ] **Step 1: Add `.gitignore` entries so no local env file is ever committed**

```
.env
.env.*
```

- [ ] **Step 2: Log in to Fly (manual, one-time)**

Run: `fly auth login`
Expected: opens a browser to authenticate your Fly.io account.

- [ ] **Step 3: Launch the app without deploying yet, so `fly.toml` can be reviewed first**

Run: `cd notes-api && fly launch --no-deploy --name mtt-notes-api`
Expected: detects the Dockerfile, asks for a region, generates `fly.toml`. Decline Fly's offer to auto-provision Postgres here — Task 5 Step 4 does that explicitly so the attach step is visible.

- [ ] **Step 4: Replace the generated `fly.toml` with this (adjust `app`/`primary_region` to match what `fly launch` picked)**

```toml
app = "mtt-notes-api"
primary_region = "iad"

[build]

[http_service]
  internal_port = 8000
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
  min_machines_running = 0

[[http_service.checks]]
  interval = "15s"
  timeout = "5s"
  grace_period = "10s"
  method = "GET"
  path = "/health"
```

- [ ] **Step 5: Provision Fly Postgres and attach it**

Run: `fly postgres create --name mtt-notes-db`
Expected: provisions a managed Postgres app on Fly's private network (not publicly reachable).

Run: `fly postgres attach mtt-notes-db --app mtt-notes-api`
Expected: sets `DATABASE_URL` as a secret on `mtt-notes-api` — this is what `db.py` (Task 1) reads. No password ever touches the repo or the client.

- [ ] **Step 6: Deploy**

Run: `fly deploy`
Expected: builds the Docker image, deploys, passes the `/health` check.

- [ ] **Step 7: Verify from outside Fly**

Run: `curl https://mtt-notes-api.fly.dev/health`
Expected: `{"status":"ok"}`

Run: `curl https://mtt-notes-api.fly.dev/notes` (no auth header)
Expected: `401`, confirming the public endpoint is actually gated.

- [ ] **Step 8: Commit the deployment config**

```bash
git add notes-api/fly.toml .gitignore
git commit -m "Add Fly.io deployment config"
```

---

### Task 6: iOS — Keychain-backed auth token

**Files:**
- Create: `morethantasks/morethantasks/Persistence/Keychain.swift`
- Modify: `morethantasks/morethantasks/Persistence/AuthService.swift`
- Test: `morethantasks/morethantasksTests/AuthTests.swift`

**Interfaces:**
- Produces: `Keychain.set(_:forKey:)`, `Keychain.get(_:) -> String?`, `Keychain.delete(_:)`; `AuthService.authToken: String?` (static), consumed by `PostgresDatabase.swift` in Task 7.

- [ ] **Step 1: Add the Keychain wrapper**

```swift
//
//  Keychain.swift
//  morethantasks
//
//  Minimal Keychain Services wrapper for values too sensitive for UserDefaults
//  (currently just the auth bearer token).
//

import Foundation
import Security

enum Keychain {
    static func set(_ value: String, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 2: Write the failing test for token storage on login**

Add to `AuthTests.swift` (inside the `AuthTests` struct):

```swift
    @Test func loginSuccessStoresAuthToken() async throws {
        Keychain.delete("authToken")
        let auth = service(status: 200, json: [
            "user": ["id": 1, "email": "a@b.com"],
            "token": "test-token-123"
        ])
        try await auth.login(email: "a@b.com", password: "Password1")
        #expect(AuthService.authToken == "test-token-123")
        Keychain.delete("authToken")
    }

    @Test func loginWithoutTokenInResponseMapsToDecoding() async {
        let auth = service(status: 200, json: [
            "user": ["id": 1, "email": "a@b.com"]
        ])
        await #expect(throws: AuthError.decoding) {
            try await auth.login(email: "a@b.com", password: "Password1")
        }
    }
```

- [ ] **Step 3: Run to verify these fail**

Run (Xcode/`xcodebuild test` on the pinned simulator device id): the two new tests should FAIL — `AuthService.authToken` doesn't exist yet, and `login` doesn't require a token in the response.

- [ ] **Step 4: Update `AuthService.swift`**

```swift
    private enum Keys {
        static let userId = "loggedInUserId"
        static let userEmail = "loggedInUserEmail"
    }

    private enum KeychainKeys {
        static let authToken = "authToken"
    }

    static var authToken: String? { Keychain.get(KeychainKeys.authToken) }
```

Update `login`:

```swift
    func login(email: String, password: String) async throws {
        let (data, status) = try await post("/sessions", body: ["email": email, "password": password])
        switch status {
        case 200: break
        case 401: throw AuthError.invalidCredentials
        default:  throw AuthError.server(status)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user"] as? [String: Any],
              let userId = user["id"] as? Int,
              let serverEmail = user["email"] as? String,
              let token = json["token"] as? String else {
            throw AuthError.decoding
        }

        UserDefaults.standard.set(userId, forKey: Keys.userId)
        UserDefaults.standard.set(serverEmail, forKey: Keys.userEmail)
        Keychain.set(token, forKey: KeychainKeys.authToken)

        // Refresh the local view for this user and seed SQLite from the server
        // so an existing user isn't shown an empty app before the first sync.
        DatabaseManager.shared.userDidLogin()
    }
```

Update `logout`:

```swift
    func logout() {
        UserDefaults.standard.removeObject(forKey: Keys.userId)
        UserDefaults.standard.removeObject(forKey: Keys.userEmail)
        Keychain.delete(KeychainKeys.authToken)
    }
```

Update `deleteAccount` to send the token:

```swift
    func deleteAccount() async throws {
        let userId = UserDefaults.standard.integer(forKey: Keys.userId)
        guard userId > 0,
              let url = URL(string: "\(ServerConfig.apiBaseURL)/users/\(userId)") else {
            throw AuthError.requestFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = Self.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let status = try await send(request)
        guard (200...299).contains(status) else { throw AuthError.server(status) }

        DatabaseManager.shared.purgeLocalData(forUser: userId)
        logout()
    }
```

- [ ] **Step 5: Run the tests again**

Expected: PASS, including the two new tests and all previously-passing `AuthTests`.

- [ ] **Step 6: Commit**

```bash
git add morethantasks/morethantasks/Persistence/Keychain.swift \
        morethantasks/morethantasks/Persistence/AuthService.swift \
        morethantasks/morethantasksTests/AuthTests.swift
git commit -m "Store auth bearer token in Keychain, attach it to account deletion"
```

---

### Task 7: iOS — replace direct Postgres pull with an authenticated API call

**Files:**
- Modify: `morethantasks/morethantasks/Persistence/PostgresDatabase.swift`
- Modify: `morethantasks/morethantasks/Sync/SyncEngine.swift`
- Manual: remove the `PostgresClientKit` Swift Package dependency in Xcode (Project Settings → Package Dependencies)

**Interfaces:**
- Consumes: `GET /notes` from Task 3, `AuthService.authToken` from Task 6.
- Produces: `PostgresDatabase.fetchNotesForSync(forUser:) async -> (active: [Notes], deletedIds: [UUID])` (now `async`, no longer blocking) — consumed by `SyncEngine.fetchRemote`.

- [ ] **Step 1: Rewrite `PostgresDatabase.swift`**

```swift
//
//  PostgresDatabase.swift
//  morethantasks
//
//  Remote sync target only. The app never reads this for UI — SQLite is the
//  source of truth. These methods are the push (insert/update/delete) and
//  pull (fetchNotesForSync) against the HTTP API, authenticated via the
//  bearer token AuthService stores at login. No direct DB connection: the
//  server is the only thing that talks to Postgres.
//

import Foundation

enum PostgresPushError: Error {
    case badURL
    case encoding
    case server(Int)
}

class PostgresDatabase {

    // MARK: - Pull

    func fetchNotesForSync(forUser userId: Int) async -> (active: [Notes], deletedIds: [UUID]) {
        var active: [Notes] = []
        var deletedIds: [UUID] = []

        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/notes") else {
            return (active, deletedIds)
        }
        var request = URLRequest(url: url)
        if let token = AuthService.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return (active, deletedIds)
            }

            for row in rows {
                guard let idString = row["note_id"] as? String,
                      let id = UUID(uuidString: idString) else { continue }

                if (row["deleted"] as? Bool) == true {
                    deletedIds.append(id)
                    continue
                }

                guard let title = row["title"] as? String,
                      let body = row["body"] as? String,
                      let lastUpdatedEpoch = row["last_updated"] as? Double else { continue }

                let parentId = (row["parent_id"] as? String).flatMap { UUID(uuidString: $0) }

                active.append(Notes(
                    id: id,
                    title: title,
                    body: body,
                    parentId: parentId,
                    children: [],
                    lastUpdated: Date(timeIntervalSince1970: lastUpdatedEpoch),
                    userID: userId,
                    colorHex: row["color"] as? String,
                    tag: row["tag"] as? String
                ))
            }
        } catch {
            print("fetchNotesForSync error:", error)
        }
        return (active, deletedIds)
    }

    // MARK: - Push: Insert
    //
    // Sends the client-generated note_id so SQLite and Postgres share one id.
    // The server must INSERT with this id (ON CONFLICT (id) DO NOTHING) for
    // retries to be idempotent.

    func insert(_ note: Notes) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/notes") else {
            throw PostgresPushError.badURL
        }

        let noteData: [String: Any] = [
            "note_id": note.id.uuidString,
            "title": note.title,
            "body": note.body,
            "tag": note.tag ?? "",
            "color": note.colorHex ?? "",
            "parent_id": note.parentId?.uuidString ?? "",
            "last_updated": note.lastUpdated.timeIntervalSince1970
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: noteData) else {
            throw PostgresPushError.encoding
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        try await send(request)
    }

    // MARK: - Push: Update
    //
    // `body` is deliberately never sent here — once a note has a body CRDT,
    // body is written only via CRDTSyncClient's POST /notes/{id}/crdt_ops,
    // so this whole-note LWW path can't clobber concurrent edits.

    func update(noteId: String, title: String?, noteParent: String?, noteColor: String?, tag: String?) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/notes/\(noteId)") else {
            throw PostgresPushError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [:]
        if let title = title { body["title"] = title }
        if let noteParent = noteParent { body["parent_id"] = noteParent }
        if let noteColor = noteColor { body["color"] = noteColor }
        if let tag = tag { body["tag"] = tag }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw PostgresPushError.encoding
        }
        request.httpBody = jsonData

        try await send(request)
    }

    // MARK: - Push: Delete (server performs a soft delete / tombstone)

    func delete(noteId: UUID) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/notes/\(noteId.uuidString)") else {
            throw PostgresPushError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        try await send(request)
    }

    /// Attaches the bearer token, performs the request, and throws unless the
    /// server returns 2xx (or no HTTP status, which we treat as success to
    /// match prior behavior).
    private func send(_ request: URLRequest) async throws {
        var request = request
        if let token = AuthService.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw PostgresPushError.server(http.statusCode)
        }
    }
}
```

- [ ] **Step 2: Simplify `SyncEngine.fetchRemote` now that the pull is genuinely async, not a blocking call needing a background-thread continuation**

```swift
    private func fetchRemote(forUser userId: Int) async -> (active: [Notes], deletedIds: [UUID]) {
        await postgres.fetchNotesForSync(forUser: userId)
    }
```

(Remove the `withCheckedContinuation`/`DispatchQueue.global` wrapper that surrounded it — no longer needed.)

- [ ] **Step 3: Remove the `PostgresClientKit` package dependency (manual, in Xcode)**

In Xcode: select the `morethantasks` project → target → *Package Dependencies* tab → select `PostgresClientKit` → remove (`-`). Also confirm it's gone from the target's *Frameworks, Libraries, and Embedded Content* list.

- [ ] **Step 4: Build and run the existing test suite**

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=<pinned-device-id>'`
Expected: builds clean (no leftover `import PostgresClientKit` anywhere) and all tests pass.

- [ ] **Step 5: Commit**

```bash
git add morethantasks/morethantasks/Persistence/PostgresDatabase.swift \
        morethantasks/morethantasks/Sync/SyncEngine.swift \
        morethantasks/morethantasks.xcodeproj/project.pbxproj
git commit -m "Replace direct Postgres pull with authenticated GET /notes, drop PostgresClientKit"
```

---

### Task 8: iOS — point at Fly, prep for TestFlight

**Files:**
- Modify: `morethantasks/morethantasks/Persistence/ServerConfig.swift`
- Modify: `morethantasks/morethantasks.xcodeproj/project.pbxproj` (version bump)
- Manual: App Store Connect record, archive/upload, TestFlight external group

**Interfaces:**
- Consumes: the deployed Fly URL from Task 5.

- [ ] **Step 1: Point `ServerConfig` at the Fly app**

```swift
//
//  ServerConfig.swift
//  morethantasks
//
//  Single source of truth for the backend address.
//

import Foundation

enum ServerConfig {
    static var apiBaseURL: String { "https://mtt-notes-api.fly.dev" }
}
```

- [ ] **Step 2: Manually smoke-test against the real deployment**

Run the app on a simulator or device, log in/register, create a note, background/foreground to trigger a sync.
Expected: note round-trips through `https://mtt-notes-api.fly.dev`, confirmed via `fly logs -a mtt-notes-api`.

- [ ] **Step 3: Bump `CURRENT_PROJECT_VERSION` (build number) in the Xcode project**

In Xcode: target → *General* → *Build* field (or *Signing & Capabilities*), increment from `1` to `2`. `MARKETING_VERSION` (`1.0`) can stay unless you want to signal this as a distinct release.

- [ ] **Step 4: Create the App Store Connect record (manual, one-time)**

Go to appstoreconnect.apple.com → *My Apps* → *+* → *New App*. Platform: iOS. Bundle ID: `personal.morethantasks` (must already be registered under team `24UM9M6NLT`, or register it in the Apple Developer portal first). Name/SKU as you prefer.

- [ ] **Step 5: Archive and upload (manual, in Xcode)**

Xcode → *Product* → *Archive* (select "Any iOS Device" or a real device as the run destination first, not a simulator). In the Organizer window that opens: *Distribute App* → *App Store Connect* → *Upload*. Xcode handles signing automatically given `CODE_SIGN_STYLE = Automatic` and the existing `DEVELOPMENT_TEAM`.

- [ ] **Step 6: Set up TestFlight**

In App Store Connect → your app → *TestFlight* tab: wait for the build to finish processing, answer the export-compliance question (this app makes no custom encryption, so "No" / HTTPS-only is fine), then create an *External Testing* group, add it to the build, and submit for the one-time beta review. Add testers by email once approved.

- [ ] **Step 7: Commit the app-facing changes**

```bash
git add morethantasks/morethantasks/Persistence/ServerConfig.swift morethantasks/morethantasks.xcodeproj/project.pbxproj
git commit -m "Point ServerConfig at the Fly.io deployment, bump build number for TestFlight"
```

---

## Self-Review Notes

- **Spec coverage:** Fly.io hosting (Tasks 4–5), public-repo secret safety (Tasks 1, 5 step 1, global constraints), TestFlight (Task 8), and the two architectural blockers raised during planning — direct DB access (Task 7) and missing auth (Tasks 2–3) — are all covered.
- **No placeholders:** every step has literal code or an exact command.
- **Type consistency:** `get_current_user_id(authorization: str | None) -> int` is defined once in Task 2 and used identically in Tasks 3's `Depends(...)` calls; `Keychain.set/get/delete(key: String)` defined in Task 6 matches every call site in Tasks 6–7; `fetchNotesForSync` is `async` (no `throws`) everywhere it's declared and called.
