# Collaborative Editing — Design Spec

**Date:** 2026-06-02
**Status:** Approved (design), pending implementation plan
**Feature:** Multi-user collaborative editing of note bodies via a hand-rolled RGA CRDT.

## Summary

Let multiple different users edit the same note concurrently, with conflict-free
merge of the note **body** via a plain-text sequence CRDT (RGA) implemented in
pure Swift. Changes propagate in a few seconds by polling over the existing
REST/FastAPI stack while a shared note is open. Sharing is flat (invite by
email, all collaborators are equal editors). Built to fit the app's existing
offline-first architecture (SQLite local store + outbox + Postgres server, with
client-side reconciliation).

### Decisions locked in brainstorming
- **Who collaborates:** multiple different users (not just one user's devices).
- **Sharing model:** invite by email, all invited users are equal editors.
- **Propagation:** a few seconds — poll the open note's CRDT ops every ~2–3s
  over REST. No WebSockets.
- **Merge style:** eventual, conflict-free (CRDT), must merge offline edits too.
- **CRDT engine:** hand-rolled RGA in pure Swift (no third-party CRDT, no native
  dependency). Correctness owned by us → heavy convergence testing.
- **Body only:** only `body` becomes CRDT. `title`, `color`, `tag`, `parent_id`,
  create/delete keep the existing whole-note last-write-wins (LWW) sync.

## Context (existing system)

- **Client:** SwiftUI app, MVVM/Combine. Note `body` is a plain `String` edited
  in a `TextEditor` (`Views/NoteView.swift`).
- **Local store:** `SQLiteDatabase` + `SyncQueueManager` outbox of
  `SyncOperation` (insert/update/delete, JSON payload, retry).
- **Sync:** `Sync/SyncEngine.swift` runs push-then-pull passes. Reconciliation is
  whole-note LWW on `lastUpdated`; deletes are tombstones. Pull is scoped per
  user (`fetchNotesForSync(forUser:)`) and refuses to run with an unknown user.
- **Server:** FastAPI (`notes-api/`) + Postgres. `notes` table has
  `id, title, body, parent_id, last_updated, user_id, color, tag, deleted`.
  Single integer `user_id` owner per note. No sharing concept exists.

### The problem this solves
`edit_note` writes `body` via whole-field LWW. If two users edit the same note,
one user's body edits silently clobber the other's. A sequence CRDT on `body`
replaces clobbering with conflict-free merge.

## Architecture overview

The body's source of truth becomes an **append-only log of RGA character
operations**. The `body` text column survives only as a **materialized cache**
for display/search/back-compat — it is derived, never authoritative.

The server **never interprets** the CRDT. It stores ops and returns them by a
monotonic per-note cursor. All merging happens on the client, consistent with
the existing client-side reconciliation design.

The body CRDT runs as a **parallel, op-granular sync channel**, separate from the
coarse whole-note outbox (whose LWW would clobber concurrent body edits).

## Section 1 — Data model & storage

### Postgres (new)
- `note_crdt_ops` — append-only, server's source of truth for body:
  - `op_id` UUID PRIMARY KEY (idempotent retries / dedupe)
  - `note_id` UUID
  - `op_type` text (`insert` | `delete`)
  - `char` text (single character; null for delete)
  - `after_id` text (the CharID this was inserted after; null = document start)
  - `lamport` bigint
  - `site_id` UUID
  - `server_seq` bigserial (monotonic per fetch ordering / poll cursor)
  - index on `(note_id, server_seq)`
- `note_collaborators`:
  - `note_id` UUID, `user_id` int, `added_at` timestamp
  - PRIMARY KEY `(note_id, user_id)` (idempotent invites)
- `notes.body` — unchanged column, now a cache written only by the CRDT endpoint.

### SQLite (client, new)
- `note_crdt_ops` — local replica of applied ops (rebuild RGA offline).
- `crdt_op_outbox` — locally-generated ops not yet pushed (op-granular; parallel
  to the existing `SyncQueueManager`).
- per-note `last_seen_server_seq` cursor.

### Migration
Add via the existing idempotent `ensure_sync_schema()` pattern in
`notes-api/db.py` (`CREATE TABLE IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS`).

## Section 2 — RGA engine & editor integration

Pure, offline-testable unit. Knows nothing about networking, SQLite, or SwiftUI.
Input: ops. Output: ordered text + ops to broadcast.

### Identity
```swift
struct CharID: Comparable { let lamport: UInt64; let siteId: UUID }
```
- `siteId`: stable **per-installation** UUID (same user on two devices = two
  distinct sites).
- `lamport`: logical clock, incremented on every local op and on receiving any
  remote op (set to `max(local, remote) + 1`).
- Total order: compare `lamport`, tie-break on `siteId`.

### Element & document
```swift
struct RGAElement { let id: CharID; let afterId: CharID?; let char: Character; var deleted: Bool }
```
- Document = ordered list of elements. Visible text = non-deleted elements
  concatenated in order.
- Concurrent inserts after the **same** `afterId` are ordered deterministically
  by **descending `CharID`**. This rule guarantees replica convergence.

### Operations (commutative + idempotent)
- `insert(id, afterId, char)` — place after `afterId`; order among siblings by ID.
- `delete(id)` — tombstone the element (kept so it can still anchor others).

### Out-of-order safety
An op whose dependency (`afterId`, or the delete target) has not arrived yet goes
to a **pending buffer**, applied the moment the dependency lands. Applying any op
twice is a no-op (dedupe by `op_id`). This is what makes offline edits and
arbitrary network ordering merge cleanly.

### TextEditor integration (riskiest unit — own tests)
SwiftUI `TextEditor` provides the whole new `String` per change, not keystroke
deltas. On each change:
1. Diff old vs new text (common prefix + common suffix → changed middle span).
2. Translate the span into `delete` ops (removed chars, by element ID) +
   `insert` ops (added chars, anchored to the element before the change point).
3. Apply locally → re-materialize → enqueue ops to `crdt_op_outbox`.

This diff→ops translation is isolated into its own unit and fuzz-tested.

## Section 3 — Sync & transport

Body CRDT uses two new endpoints. `title/color/tag/parent_id` keep the existing
`edit_note` LWW path.

### Endpoints
- `POST /notes/{id}/crdt_ops` — append a batch of local ops. Server inserts into
  `note_crdt_ops` (PK `op_id` → duplicates ignored), assigns `server_seq`, and
  updates cached `notes.body` from a materialized-text snapshot in the request.
  Authorizes: caller is owner OR collaborator.
- `GET /notes/{id}/crdt_ops?since=<server_seq>` — return ops with
  `server_seq > since`, ordered. Cursor-based pull. Authorizes: owner OR
  collaborator.

### Poll-while-open (client)
While a shared note is open, a timer fires ~every 2–3s and calls `GET` with the
note's `last_seen_server_seq`; new ops are applied to the RGA, text
re-materializes, cursor advances. Loop stops on note close. Local edits push on a
debounced cadence (~1s after typing pauses) via `POST`.

### Offline
Offline ops accumulate in `crdt_op_outbox`, push on reconnect; the next poll
pulls everything missed since the cursor. Conflict-free merge means catch-up
order is irrelevant — replicas converge regardless of who was offline.

### Relationship to existing SyncEngine
- `title`, `color`, `tag`, `parent_id`, create/delete/tombstone → unchanged,
  still flow through the existing push-then-pull `SyncEngine`.
- `body` → **removed from the LWW write path**. Server `edit_note` stops
  accepting `body`; `body` is written only by the CRDT endpoint's cache snapshot.
  This prevents two writers fighting over `body`.

## Section 4 — Sharing & permissions

- Flat, all-editors. Owner in `notes.user_id`; collaborators are
  `note_collaborators` rows. Identical edit rights.
- **Owner-only invites** for v1.
- `POST /notes/{id}/invite { email }` — look up user by email in `users`. Found →
  insert collaborator row (idempotent). Not found → clear "no such user" error
  (v1 shares only with existing accounts; email-to-signup is out of scope).
  Owner-only.
- **Pull-scoping change:** `fetchNotesForSync(forUser:)` (and any per-user note
  listing) returns notes where `user_id = me` OR
  `id IN (SELECT note_id FROM note_collaborators WHERE user_id = me)`. This is how
  a shared note reaches the invitee's device.
- **CRDT endpoint authorization:** both ops endpoints verify caller is owner or
  collaborator.
- **Minimal SwiftUI UI:** a "Share" affordance → enter email → invite; a simple
  collaborator list. No presence/cursors/avatars.

## Section 5 — Error handling & testing

### Error handling
- Out-of-order / missing-dependency ops → pending buffer, applied when dependency
  arrives. Never dropped, never applied early.
- Idempotency everywhere: dedupe by `op_id` (PK in Postgres and SQLite). Push
  retries, double-delivery, replays are safe.
- Cursor integrity: `last_seen_server_seq` advances only after ops are durably
  applied locally; a crash mid-pull re-fetches rather than skips.
- `body` cache lag: a stale snapshot only affects the display cache; the op log
  is truth and the next rebuild corrects it. No data loss.
- Network/auth failures: existing retry semantics on the sync channel; clear
  errors for invalid invites / unauthorized ops access.

### Testing (encodes WHY, per project Rule 9)
1. **Convergence (core invariant):** random interleavings of the same op set
   across N simulated sites → identical materialized text on every site. Fails
   the instant merge logic is wrong; this test justifies hand-rolled RGA.
2. **Commutativity & idempotency:** any order + duplicates → same result.
3. **Concurrent-insert determinism:** two sites insert at the same position
   offline → same deterministic order.
4. **Diff→ops correctness:** fuzzed `(oldText, newText)` → generated ops applied
   to old RGA reproduce `newText` exactly.
5. **Integration:** two in-memory clients edit offline, sync, converge —
   including a delete racing an insert on the same char.

## Out of scope (explicit YAGNI for v1)
- Live cursors / presence / avatars.
- Op-log compaction / tombstone GC (accepted growth for small notes).
- Roles / viewer tier (all collaborators are equal editors).
- Email-to-signup invites (share only with existing accounts).
- Rich text / formatting (plain-text body only).
- WebSocket transport (poll-while-open only).

## Suggested implementation phases (for the plan)
1. RGA engine + convergence/diff tests (pure Swift, no I/O).
2. Local storage (SQLite ops tables, outbox, cursor) + editor integration.
3. Server: schema migration, `crdt_ops` endpoints, body removed from LWW path.
4. Poll-while-open loop + debounced push wiring.
5. Sharing: `note_collaborators`, invite endpoint, pull-scope change, auth, UI.
