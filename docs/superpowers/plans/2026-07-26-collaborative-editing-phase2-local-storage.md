# Collaborative Editing Phase 2 — Local Storage & Editor Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the already-built RGA CRDT engine (Phase 1: `CharID`/`RGAOp`/`RGADocument`/`RGAEditor`) a local home in SQLite and wire it into `NoteDetailView`'s `TextEditor`, so note bodies are edited through the CRDT instead of a plain string, entirely offline (no networking — that is Phase 3).

**Architecture:** A new `CRDTStore` (own SQLite file, same pattern as `SyncQueueManager`) persists the applied op log, an outbox of unpushed ops, and a per-note sync cursor — none of which any networking code reads yet. A new `CRDTNoteBodyController` rehydrates an `RGADocument` from `CRDTStore` for one note, seeds it from the note's existing `body` text the first time it's touched, and turns `TextEditor` diffs into ops via the existing `RGAEditor`. `DatabaseManager` seeds ops on note creation and purges them on note deletion. `NoteDetailView` routes its `TextEditor` through the controller instead of editing `text` directly.

**Tech Stack:** Swift, SQLite3 (C API, matching `SQLiteDatabase`/`SyncQueueManager`), Swift Testing (`@Test`, `#expect`), SwiftUI.

## Global Constraints

- No networking, server schema, or sync-loop code in this phase — see `docs/superpowers/specs/2026-06-02-collaborative-editing-design.md` Section 3, phases 3-4. `CRDTStore`'s outbox/cursor tables are written and readable but nothing drains them yet.
- Only `body` becomes CRDT — `title`, `color`, `tag`, `parent_id` keep flowing through the existing `DatabaseManager`/`SyncQueueManager` LWW path unchanged (spec, "Decisions locked in").
- `siteId` is a stable per-installation UUID, not synced across devices (spec Section 2, "Identity").
- Follow existing file conventions: raw `SQLite3` C API, one dedicated `.sqlite` file per manager, singleton `.shared`, `INSERT OR REPLACE`/`INSERT OR IGNORE` for idempotency — see `morethantasks/morethantasks/Sync/SyncQueueManager.swift`.
- Per project test-cadence convention: run only the single new test file after each task (`xcodebuild test -only-testing:...`); run the full suite once at the end, not per task.

---

## File Structure

- Create: `morethantasks/morethantasks/CRDT/CRDTSite.swift` — per-installation site id.
- Create: `morethantasks/morethantasks/CRDT/CRDTStore.swift` — SQLite persistence for ops/outbox/cursor.
- Create: `morethantasks/morethantasks/CRDT/CRDTNoteBodyController.swift` — per-note RGA rehydration + seeding + local-edit translation.
- Modify: `morethantasks/morethantasks/Managers/DatabaseManager.swift` — seed CRDT ops on insert, purge on delete.
- Modify: `morethantasks/morethantasks/Views/NoteView.swift` — `NoteDetailView` routes `TextEditor` through the controller.
- Test: `morethantasks/morethantasksTests/CRDTSiteTests.swift`
- Test: `morethantasks/morethantasksTests/CRDTStoreTests.swift`
- Test: `morethantasks/morethantasksTests/CRDTNoteBodyControllerTests.swift`

**Simulator used for all `-only-testing` runs in this plan:** `platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38` (iPhone 16 Pro). Pinned so results are comparable across tasks.

---

### Task 1: CRDTSite — per-installation site id

**Files:**
- Create: `morethantasks/morethantasks/CRDT/CRDTSite.swift`
- Test: `morethantasks/morethantasksTests/CRDTSiteTests.swift`

**Interfaces:**
- Produces: `enum CRDTSite { static func id(using defaults: UserDefaults = .standard) -> UUID }` — later tasks call `CRDTSite.id()` to get the local `RGAEditor`'s `siteId`.

- [ ] **Step 1: Write the failing test**

```swift
//  CRDTSiteTests.swift
import Testing
import Foundation
@testable import morethantasks

struct CRDTSiteTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "CRDTSiteTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test func generatesAndPersistsAnIdOnFirstCall() {
        let defaults = freshDefaults()
        let first = CRDTSite.id(using: defaults)
        let second = CRDTSite.id(using: defaults)
        #expect(first == second)
    }

    @Test func differentDefaultsSuitesGetDifferentIds() {
        let a = CRDTSite.id(using: freshDefaults())
        let b = CRDTSite.id(using: freshDefaults())
        #expect(a != b)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38' -only-testing:morethantasksTests/CRDTSiteTests`
Expected: FAIL to build — `CRDTSite` does not exist.

- [ ] **Step 3: Write minimal implementation**

```swift
//  CRDTSite.swift
//  Stable per-installation identity for the local RGA CRDT engine. NOT synced
//  across devices — the same user on two devices is deliberately two sites
//  (see docs/superpowers/specs/2026-06-02-collaborative-editing-design.md,
//  Section 2 "Identity").
import Foundation

enum CRDTSite {
    private static let key = "crdtSiteId"

    static func id(using defaults: UserDefaults = .standard) -> UUID {
        if let stored = defaults.string(forKey: key), let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let fresh = UUID()
        defaults.set(fresh.uuidString, forKey: key)
        return fresh
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38' -only-testing:morethantasksTests/CRDTSiteTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add morethantasks/morethantasks/CRDT/CRDTSite.swift morethantasks/morethantasksTests/CRDTSiteTests.swift
git commit -m "feat(crdt): add per-installation site id"
```

---

### Task 2: CRDTStore — schema + applied-op log (append/fetch/hasOps)

**Files:**
- Create: `morethantasks/morethantasks/CRDT/CRDTStore.swift`
- Test: `morethantasks/morethantasksTests/CRDTStoreTests.swift`

**Interfaces:**
- Consumes: `RGAOp` (`type: RGAOpType`, `id: CharID`, `parentId: CharID?`, `char: String?`), `CharID` (`lamport: UInt64`, `siteId: UUID`) — from `morethantasks/morethantasks/CRDT/RGAOp.swift` and `CharID.swift`.
- Produces: `final class CRDTStore { static let shared: CRDTStore; init(dbPath: String = "CRDTOps.sqlite"); func appendOps(_ ops: [RGAOp], noteId: UUID); func fetchOps(forNote noteId: UUID) -> [RGAOp]; func hasOps(forNote noteId: UUID) -> Bool }` — Task 5 (`CRDTNoteBodyController`) rehydrates a document via `fetchOps` and checks `hasOps` before seeding.
- `dbPath == ":memory:"` opens an isolated in-memory database (for tests); any other value resolves inside the app's Documents directory, same as `SQLiteDatabase`/`SyncQueueManager`.

- [ ] **Step 1: Write the failing test**

```swift
//  CRDTStoreTests.swift
import Testing
import Foundation
@testable import morethantasks

struct CRDTStoreTests {
    private func makeStore() -> CRDTStore { CRDTStore(dbPath: ":memory:") }

    private func site() -> (UInt64) -> CharID {
        let s = UUID()
        return { lamport in CharID(lamport: lamport, siteId: s) }
    }

    @Test func newNoteHasNoOps() {
        let store = makeStore()
        #expect(store.hasOps(forNote: UUID()) == false)
    }

    @Test func appendThenFetchReturnsTheSameOps() {
        let store = makeStore()
        let noteId = UUID()
        let id = site()
        let a = id(1)
        let op = RGAOp(type: .insert, id: a, parentId: nil, char: "x")

        store.appendOps([op], noteId: noteId)

        #expect(store.hasOps(forNote: noteId) == true)
        #expect(store.fetchOps(forNote: noteId) == [op])
    }

    @Test func appendingTheSameOpTwiceDoesNotDuplicateIt() {
        let store = makeStore()
        let noteId = UUID()
        let id = site()
        let op = RGAOp(type: .insert, id: id(1), parentId: nil, char: "x")

        store.appendOps([op], noteId: noteId)
        store.appendOps([op], noteId: noteId)

        #expect(store.fetchOps(forNote: noteId).count == 1)
    }

    @Test func opsFromDifferentNotesDoNotLeakIntoEachOther() {
        let store = makeStore()
        let noteA = UUID()
        let noteB = UUID()
        let id = site()
        store.appendOps([RGAOp(type: .insert, id: id(1), parentId: nil, char: "a")], noteId: noteA)

        #expect(store.fetchOps(forNote: noteA).count == 1)
        #expect(store.fetchOps(forNote: noteB).isEmpty)
    }

    @Test func fetchOpsOrdersByLamportAscending() {
        let store = makeStore()
        let noteId = UUID()
        let id = site()
        let a = id(1); let b = id(2); let c = id(3)
        // Insert out of lamport order to prove fetch re-sorts, not just echoes insert order.
        store.appendOps([
            RGAOp(type: .insert, id: c, parentId: b, char: "c"),
            RGAOp(type: .insert, id: a, parentId: nil, char: "a"),
            RGAOp(type: .insert, id: b, parentId: a, char: "b"),
        ], noteId: noteId)

        #expect(store.fetchOps(forNote: noteId).map(\.id.lamport) == [1, 2, 3])
    }

    @Test func deleteOpRoundTripsWithNilCharAndNilParent() {
        let store = makeStore()
        let noteId = UUID()
        let id = site()
        let del = RGAOp(type: .delete, id: id(5), parentId: nil, char: nil)

        store.appendOps([del], noteId: noteId)

        #expect(store.fetchOps(forNote: noteId) == [del])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38' -only-testing:morethantasksTests/CRDTStoreTests`
Expected: FAIL to build — `CRDTStore` does not exist.

- [ ] **Step 3: Write minimal implementation**

```swift
//  CRDTStore.swift
//  Local SQLite home for the RGA CRDT op log (see RGADocument/RGAOp). Three
//  tables, one file, same pattern as SyncQueueManager:
//    - note_crdt_ops: applied log, source of truth for rehydrating a note's
//      RGADocument on next launch.
//    - crdt_op_outbox: locally-generated ops not yet pushed to the server.
//      Nothing drains this yet — that's Phase 3/4 (see design spec).
//    - crdt_cursor: per-note last_seen_server_seq poll cursor. Unused until
//      Phase 4's poll loop exists; created now so the schema is stable.
//  An op's identity is (note_id, lamport, site_id) — encoded as a single
//  TEXT primary key so INSERT OR IGNORE gives free idempotent dedup.
import SQLite3
import Foundation

final class CRDTStore {
    static let shared = CRDTStore()

    private var db: OpaquePointer?

    init(dbPath: String = "CRDTOps.sqlite") {
        db = Self.openDatabase(dbPath)
        createTables()
    }

    private static func openDatabase(_ dbPath: String) -> OpaquePointer? {
        var db: OpaquePointer? = nil
        if dbPath == ":memory:" {
            if sqlite3_open(":memory:", &db) != SQLITE_OK {
                debugPrint("Cannot open in-memory CRDT store.")
                return nil
            }
            return db
        }
        let filePath = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(dbPath)
        if sqlite3_open(filePath.path, &db) != SQLITE_OK {
            debugPrint("Cannot open CRDT store DB at \(filePath.path).")
            return nil
        }
        return db
    }

    private func createTables() {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS note_crdt_ops (
                op_key TEXT PRIMARY KEY,
                note_id TEXT NOT NULL,
                op_type TEXT NOT NULL,
                lamport INTEGER NOT NULL,
                site_id TEXT NOT NULL,
                parent_lamport INTEGER,
                parent_site_id TEXT,
                char TEXT
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_crdt_ops_note ON note_crdt_ops(note_id);",
            """
            CREATE TABLE IF NOT EXISTS crdt_op_outbox (
                op_key TEXT PRIMARY KEY,
                note_id TEXT NOT NULL,
                op_type TEXT NOT NULL,
                lamport INTEGER NOT NULL,
                site_id TEXT NOT NULL,
                parent_lamport INTEGER,
                parent_site_id TEXT,
                char TEXT
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_crdt_outbox_note ON crdt_op_outbox(note_id);",
            """
            CREATE TABLE IF NOT EXISTS crdt_cursor (
                note_id TEXT PRIMARY KEY,
                last_seen_server_seq INTEGER NOT NULL DEFAULT 0
            );
            """,
        ]
        for sql in statements {
            var statement: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("CRDTStore: statement failed to execute: \(sql)")
                }
            } else {
                print("CRDTStore: statement failed to prepare: \(sql)")
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - Op key encoding

    private func opKey(noteId: UUID, id: CharID) -> String {
        "\(noteId.uuidString)|\(id.lamport)|\(id.siteId.uuidString)"
    }

    // MARK: - Applied log

    func appendOps(_ ops: [RGAOp], noteId: UUID) {
        for op in ops {
            insert(op, noteId: noteId, into: "note_crdt_ops")
            insert(op, noteId: noteId, into: "crdt_op_outbox")
        }
    }

    private func insert(_ op: RGAOp, noteId: UUID, into table: String) {
        let sql = """
        INSERT OR IGNORE INTO \(table)
        (op_key, note_id, op_type, lamport, site_id, parent_lamport, parent_site_id, char)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("CRDTStore: failed to prepare insert into \(table).")
            sqlite3_finalize(statement)
            return
        }
        sqlite3_bind_text(statement, 1, (opKey(noteId: noteId, id: op.id) as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (noteId.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (op.type.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 4, Int64(op.id.lamport))
        sqlite3_bind_text(statement, 5, (op.id.siteId.uuidString as NSString).utf8String, -1, nil)
        if let parent = op.parentId {
            sqlite3_bind_int64(statement, 6, Int64(parent.lamport))
            sqlite3_bind_text(statement, 7, (parent.siteId.uuidString as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 6)
            sqlite3_bind_null(statement, 7)
        }
        if let char = op.char {
            sqlite3_bind_text(statement, 8, (char as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 8)
        }
        if sqlite3_step(statement) != SQLITE_DONE {
            print("CRDTStore: failed to insert op into \(table).")
        }
        sqlite3_finalize(statement)
    }

    func fetchOps(forNote noteId: UUID) -> [RGAOp] {
        fetchRows(from: "note_crdt_ops", noteId: noteId)
    }

    func hasOps(forNote noteId: UUID) -> Bool {
        let sql = "SELECT COUNT(*) FROM note_crdt_ops WHERE note_id = ?;"
        var statement: OpaquePointer? = nil
        var count = 0
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (noteId.uuidString as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return count > 0
    }

    private func fetchRows(from table: String, noteId: UUID) -> [RGAOp] {
        let sql = """
        SELECT op_type, lamport, site_id, parent_lamport, parent_site_id, char
        FROM \(table) WHERE note_id = ? ORDER BY lamport ASC, site_id ASC;
        """
        var statement: OpaquePointer? = nil
        var ops: [RGAOp] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return ops
        }
        sqlite3_bind_text(statement, 1, (noteId.uuidString as NSString).utf8String, -1, nil)
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let typeC = sqlite3_column_text(statement, 0),
                  let type = RGAOpType(rawValue: String(cString: typeC)),
                  let siteIdC = sqlite3_column_text(statement, 2),
                  let siteId = UUID(uuidString: String(cString: siteIdC)) else { continue }

            let lamport = UInt64(sqlite3_column_int64(statement, 1))
            let id = CharID(lamport: lamport, siteId: siteId)

            var parentId: CharID? = nil
            if sqlite3_column_type(statement, 3) != SQLITE_NULL,
               let parentSiteIdC = sqlite3_column_text(statement, 4),
               let parentSiteId = UUID(uuidString: String(cString: parentSiteIdC)) {
                let parentLamport = UInt64(sqlite3_column_int64(statement, 3))
                parentId = CharID(lamport: parentLamport, siteId: parentSiteId)
            }

            let char = sqlite3_column_text(statement, 5).map { String(cString: $0) }

            ops.append(RGAOp(type: type, id: id, parentId: parentId, char: char))
        }
        sqlite3_finalize(statement)
        return ops
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38' -only-testing:morethantasksTests/CRDTStoreTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add morethantasks/morethantasks/CRDT/CRDTStore.swift morethantasks/morethantasksTests/CRDTStoreTests.swift
git commit -m "feat(crdt): add CRDTStore applied-op log"
```

---

### Task 3: CRDTStore — outbox drain API

**Files:**
- Modify: `morethantasks/morethantasks/CRDT/CRDTStore.swift`
- Modify: `morethantasks/morethantasksTests/CRDTStoreTests.swift`

**Interfaces:**
- Produces (added to `CRDTStore`): `func fetchOutboxOps(forNote noteId: UUID) -> [RGAOp]`, `func removeFromOutbox(_ ops: [RGAOp], noteId: UUID)`.
- No consumer yet — Phase 3/4's future push loop will call these. This task only proves the outbox table can be filled (by `appendOps`, already wired in Task 2) and drained.

- [ ] **Step 1: Write the failing test**

Append to `CRDTStoreTests.swift`:

```swift
    @Test func appendOpsAlsoLandsInTheOutbox() {
        let store = makeStore()
        let noteId = UUID()
        let op = RGAOp(type: .insert, id: site()(1), parentId: nil, char: "x")

        store.appendOps([op], noteId: noteId)

        #expect(store.fetchOutboxOps(forNote: noteId) == [op])
    }

    @Test func removeFromOutboxDropsOnlyThoseOpsFromTheOutboxNotTheAppliedLog() {
        let store = makeStore()
        let noteId = UUID()
        let id = site()
        let a = RGAOp(type: .insert, id: id(1), parentId: nil, char: "a")
        let b = RGAOp(type: .insert, id: id(2), parentId: id(1), char: "b")
        store.appendOps([a, b], noteId: noteId)

        store.removeFromOutbox([a], noteId: noteId)

        #expect(store.fetchOutboxOps(forNote: noteId) == [b])
        #expect(store.fetchOps(forNote: noteId) == [a, b])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38' -only-testing:morethantasksTests/CRDTStoreTests`
Expected: FAIL to build — `fetchOutboxOps`/`removeFromOutbox` do not exist.

- [ ] **Step 3: Write minimal implementation**

Add to `CRDTStore`, near `fetchOps`/`hasOps`:

```swift
    // MARK: - Outbox (drained by a future push loop — Phase 3/4)

    func fetchOutboxOps(forNote noteId: UUID) -> [RGAOp] {
        fetchRows(from: "crdt_op_outbox", noteId: noteId)
    }

    func removeFromOutbox(_ ops: [RGAOp], noteId: UUID) {
        let sql = "DELETE FROM crdt_op_outbox WHERE op_key = ?;"
        for op in ops {
            var statement: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (opKey(noteId: noteId, id: op.id) as NSString).utf8String, -1, nil)
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("CRDTStore: failed to remove op from outbox.")
                }
            }
            sqlite3_finalize(statement)
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38' -only-testing:morethantasksTests/CRDTStoreTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add morethantasks/morethantasks/CRDT/CRDTStore.swift morethantasks/morethantasksTests/CRDTStoreTests.swift
git commit -m "feat(crdt): add CRDTStore outbox drain API"
```

---

### Task 4: CRDTStore — cursor + per-note deletion

**Files:**
- Modify: `morethantasks/morethantasks/CRDT/CRDTStore.swift`
- Modify: `morethantasks/morethantasksTests/CRDTStoreTests.swift`

**Interfaces:**
- Produces (added to `CRDTStore`): `func cursor(forNote noteId: UUID) -> Int64` (defaults to 0), `func setCursor(forNote noteId: UUID, serverSeq: Int64)`, `func deleteAll(forNote noteId: UUID)`.
- Task 6 (`DatabaseManager`) calls `deleteAll(forNote:)` when a note is deleted, so CRDT rows don't outlive the note.

- [ ] **Step 1: Write the failing test**

Append to `CRDTStoreTests.swift`:

```swift
    @Test func cursorDefaultsToZeroForAnUnseenNote() {
        let store = makeStore()
        #expect(store.cursor(forNote: UUID()) == 0)
    }

    @Test func setCursorThenReadReturnsTheStoredValue() {
        let store = makeStore()
        let noteId = UUID()
        store.setCursor(forNote: noteId, serverSeq: 42)
        #expect(store.cursor(forNote: noteId) == 42)
    }

    @Test func setCursorTwiceOverwritesRatherThanErrors() {
        let store = makeStore()
        let noteId = UUID()
        store.setCursor(forNote: noteId, serverSeq: 1)
        store.setCursor(forNote: noteId, serverSeq: 2)
        #expect(store.cursor(forNote: noteId) == 2)
    }

    @Test func deleteAllRemovesOpsOutboxAndCursorForThatNoteOnly() {
        let store = makeStore()
        let noteId = UUID()
        let otherNoteId = UUID()
        let op = RGAOp(type: .insert, id: site()(1), parentId: nil, char: "x")
        store.appendOps([op], noteId: noteId)
        store.appendOps([op], noteId: otherNoteId)
        store.setCursor(forNote: noteId, serverSeq: 7)

        store.deleteAll(forNote: noteId)

        #expect(store.fetchOps(forNote: noteId).isEmpty)
        #expect(store.fetchOutboxOps(forNote: noteId).isEmpty)
        #expect(store.cursor(forNote: noteId) == 0)
        #expect(store.fetchOps(forNote: otherNoteId).count == 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38' -only-testing:morethantasksTests/CRDTStoreTests`
Expected: FAIL to build — `cursor`/`setCursor`/`deleteAll` do not exist.

- [ ] **Step 3: Write minimal implementation**

Add to `CRDTStore`:

```swift
    // MARK: - Cursor (unused until Phase 4's poll loop)

    func cursor(forNote noteId: UUID) -> Int64 {
        let sql = "SELECT last_seen_server_seq FROM crdt_cursor WHERE note_id = ?;"
        var statement: OpaquePointer? = nil
        var value: Int64 = 0
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (noteId.uuidString as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_ROW {
                value = sqlite3_column_int64(statement, 0)
            }
        }
        sqlite3_finalize(statement)
        return value
    }

    func setCursor(forNote noteId: UUID, serverSeq: Int64) {
        let sql = """
        INSERT OR REPLACE INTO crdt_cursor (note_id, last_seen_server_seq) VALUES (?, ?);
        """
        var statement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (noteId.uuidString as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, serverSeq)
            if sqlite3_step(statement) != SQLITE_DONE {
                print("CRDTStore: failed to set cursor.")
            }
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Deletion (called when the note itself is deleted)

    func deleteAll(forNote noteId: UUID) {
        for table in ["note_crdt_ops", "crdt_op_outbox", "crdt_cursor"] {
            let sql = "DELETE FROM \(table) WHERE note_id = ?;"
            var statement: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (noteId.uuidString as NSString).utf8String, -1, nil)
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("CRDTStore: failed to delete rows from \(table).")
                }
            }
            sqlite3_finalize(statement)
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38' -only-testing:morethantasksTests/CRDTStoreTests`
Expected: PASS (12 tests).

- [ ] **Step 5: Commit**

```bash
git add morethantasks/morethantasks/CRDT/CRDTStore.swift morethantasks/morethantasksTests/CRDTStoreTests.swift
git commit -m "feat(crdt): add CRDTStore cursor and per-note deletion"
```

---

### Task 5: CRDTNoteBodyController — rehydrate, seed, translate local edits

**Files:**
- Create: `morethantasks/morethantasks/CRDT/CRDTNoteBodyController.swift`
- Test: `morethantasks/morethantasksTests/CRDTNoteBodyControllerTests.swift`

**Interfaces:**
- Consumes: `CRDTStore` (Task 2-4: `appendOps`, `fetchOps`, `hasOps`), `RGADocument`/`RGAEditor`/`RGAOp` (Phase 1), `CRDTSite.id(using:)` (Task 1).
- Produces: `final class CRDTNoteBodyController { init(noteId: UUID, initialBody: String, store: CRDTStore = .shared, siteId: UUID = CRDTSite.id()); var materializedText: String { get }; @discardableResult func applyLocalChange(from old: String, to new: String) -> String }` — Task 6 (`DatabaseManager`) and Task 7 (`NoteDetailView`) both construct this.

- [ ] **Step 1: Write the failing test**

```swift
//  CRDTNoteBodyControllerTests.swift
import Testing
import Foundation
@testable import morethantasks

struct CRDTNoteBodyControllerTests {
    private func freshStore() -> CRDTStore { CRDTStore(dbPath: ":memory:") }

    @Test func firstOpenOfANewNoteSeedsOpsFromTheInitialBody() {
        let store = freshStore()
        let noteId = UUID()

        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "hello", store: store, siteId: UUID())

        #expect(controller.materializedText == "hello")
        #expect(store.hasOps(forNote: noteId) == true)
    }

    @Test func emptyInitialBodySeedsNoOps() {
        let store = freshStore()
        let noteId = UUID()

        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "", store: store, siteId: UUID())

        #expect(controller.materializedText == "")
        #expect(store.hasOps(forNote: noteId) == false)
    }

    @Test func applyLocalChangePersistsOpsAndReturnsTheMaterializedText() {
        let store = freshStore()
        let noteId = UUID()
        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "ab", store: store, siteId: UUID())

        let result = controller.applyLocalChange(from: "ab", to: "axb")

        #expect(result == "axb")
        // seed ops (a, b) + one insert op for x
        #expect(store.fetchOps(forNote: noteId).count == 3)
    }

    @Test func reopeningAnExistingNoteRehydratesFromStoredOpsWithoutReseeding() {
        let store = freshStore()
        let noteId = UUID()
        let first = CRDTNoteBodyController(noteId: noteId, initialBody: "hello", store: store, siteId: UUID())
        first.applyLocalChange(from: "hello", to: "hello world")
        let opCountAfterFirstSession = store.fetchOps(forNote: noteId).count

        // Simulate an app relaunch: a brand-new controller for the same note.
        let second = CRDTNoteBodyController(noteId: noteId, initialBody: "hello world", store: store, siteId: UUID())

        #expect(second.materializedText == "hello world")
        #expect(store.fetchOps(forNote: noteId).count == opCountAfterFirstSession)
    }

    @Test func noOpChangeAppendsNoOps() {
        let store = freshStore()
        let noteId = UUID()
        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "same", store: store, siteId: UUID())
        let opCountAfterSeed = store.fetchOps(forNote: noteId).count

        let result = controller.applyLocalChange(from: "same", to: "same")

        #expect(result == "same")
        #expect(store.fetchOps(forNote: noteId).count == opCountAfterSeed)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38' -only-testing:morethantasksTests/CRDTNoteBodyControllerTests`
Expected: FAIL to build — `CRDTNoteBodyController` does not exist.

- [ ] **Step 3: Write minimal implementation**

```swift
//  CRDTNoteBodyController.swift
//  Owns one note's RGA document for its lifetime in memory: rehydrates it from
//  CRDTStore's applied log, seeds it from the note's existing `body` the first
//  time the note is touched (fresh note, or a pre-CRDT note with no ops yet),
//  and turns TextEditor diffs into ops via RGAEditor, persisting them as it goes.
import Foundation

final class CRDTNoteBodyController {
    let noteId: UUID

    private let store: CRDTStore
    private let document: RGADocument
    private let editor: RGAEditor

    init(noteId: UUID, initialBody: String, store: CRDTStore = .shared, siteId: UUID = CRDTSite.id()) {
        self.noteId = noteId
        self.store = store
        self.document = RGADocument()

        let existingOps = store.fetchOps(forNote: noteId)
        for op in existingOps { document.apply(op) }

        self.editor = RGAEditor(document: document, siteId: siteId)

        if existingOps.isEmpty {
            let seedOps = editor.applyLocalChange(from: "", to: initialBody)
            if !seedOps.isEmpty { store.appendOps(seedOps, noteId: noteId) }
        }
    }

    var materializedText: String { document.text() }

    @discardableResult
    func applyLocalChange(from old: String, to new: String) -> String {
        let ops = editor.applyLocalChange(from: old, to: new)
        if !ops.isEmpty { store.appendOps(ops, noteId: noteId) }
        return document.text()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38' -only-testing:morethantasksTests/CRDTNoteBodyControllerTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add morethantasks/morethantasks/CRDT/CRDTNoteBodyController.swift morethantasks/morethantasksTests/CRDTNoteBodyControllerTests.swift
git commit -m "feat(crdt): add CRDTNoteBodyController"
```

---

### Task 6: Wire CRDT seeding/cleanup into DatabaseManager

**Files:**
- Modify: `morethantasks/morethantasks/Managers/DatabaseManager.swift:97-112` (`insert`), `:137-145` (`delete`)

**Interfaces:**
- Consumes: `CRDTNoteBodyController.init(noteId:initialBody:)` (Task 5, seeds as a side effect when no ops exist yet), `CRDTStore.shared.deleteAll(forNote:)` (Task 4).
- No new public interface — this task only changes `DatabaseManager`'s existing `insert`/`delete` bodies.

This task has no isolated unit test: `DatabaseManager` is `@MainActor` and talks to real `SQLiteDatabase`/`PostgresDatabase`/`SyncQueueManager` instances with no seams for injection (consistent with the rest of the file — it isn't unit-tested today either). Correctness is verified by the build succeeding and by the manual end-to-end check in Task 7.

- [ ] **Step 1: Seed CRDT ops when a note is inserted**

In `morethantasks/morethantasks/Managers/DatabaseManager.swift`, `insert(note:)`:

```swift
    func insert(note: Notes) {
        guard !notesArray.contains(where: { $0.id == note.id }) else {
            print("Note with id \(note.id) already exists locally.")
            return
        }
        var stamped = note
        stamped.userID = currentUserId   // the view passes userID 0; stamp the real one here

        sqlite.insert(stamped) {
            Task { @MainActor in
                self.notesArray.append(stamped)
                self.rebuildTags()
                self.enqueue(.insert, note: stamped)
                _ = CRDTNoteBodyController(noteId: stamped.id, initialBody: stamped.body)
            }
        }
    }
```

- [ ] **Step 2: Purge CRDT rows when a note is deleted**

In the same file, `delete(noteId:)`:

```swift
    func delete(noteId: UUID) {
        sqlite.delete(noteId: noteId) {
            Task { @MainActor in
                self.notesArray.removeAll { $0.id == noteId }
                self.rebuildTags()
                self.enqueueDelete(noteId)
                CRDTStore.shared.deleteAll(forNote: noteId)
            }
        }
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add morethantasks/morethantasks/Managers/DatabaseManager.swift
git commit -m "feat(crdt): seed CRDT ops on note insert, purge on note delete"
```

---

### Task 7: Route NoteDetailView's TextEditor through the CRDT controller

**Files:**
- Modify: `morethantasks/morethantasks/Views/NoteView.swift:318-368` (`NoteDetailView`)

**Interfaces:**
- Consumes: `CRDTNoteBodyController.init(noteId:initialBody:)`, `.materializedText`, `.applyLocalChange(from:to:)` (Task 5).

This task changes SwiftUI view code with no existing UI test target covering `NoteView` (`morethantasksUITests` only covers app launch). Verify by building and manually exercising the note editor in the simulator — this is stated explicitly per project convention (Rule 12: don't claim a UI change works without having driven it).

- [ ] **Step 1: Hold a controller per opened note and seed `text` from its materialized output**

In `morethantasks/morethantasks/Views/NoteView.swift`, replace the `NoteDetailView` struct:

```swift
// MARK: - Note Detail View
struct NoteDetailView: View {
    let note: Notes
    @Binding var tagsArray: [String]

    @State var title: String
    @State var text: String
    @State var tag: String = ""
    @State private var bodyController: CRDTNoteBodyController

    var onSave: ((String, String, String) -> Void)?

    init(note: Notes, tagsArray: Binding<[String]>, onSave: ((String, String, String) -> Void)? = nil) {
        self.note = note
        self._tagsArray = tagsArray
        let controller = CRDTNoteBodyController(noteId: note.id, initialBody: note.body)
        _bodyController = State(initialValue: controller)
        _title = State(initialValue: note.title)
        _text = State(initialValue: controller.materializedText)
        _tag = State(initialValue: note.tag ?? "")
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TagSelection(existingTags: tagsArray, tag: $tag)
                    .onChange(of: tag) { oldValue, newValue in
                        onSave?(title, text, newValue)
                    }

                TextField("Title", text: $title, axis: .vertical)
                    .font(.largeTitle.bold())
                    .textInputAutocapitalization(.never)
                    .onChange(of: title) { oldValue, newValue in
                        onSave?(newValue, text, tag)
                    }

                TextEditor(text: $text)
                    .font(.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 400)
                    .onChange(of: text) { oldValue, newValue in
                        let materialized = bodyController.applyLocalChange(from: oldValue, to: newValue)
                        onSave?(title, materialized, tag)
                    }
            }
            .padding()
        }
        .navigationTitle(title.isEmpty ? "Untitled" : title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke test in the simulator**

Boot the pinned simulator, run the app, and:
1. Create a new note with some body text, save it, reopen it — text must round-trip unchanged.
2. Edit the body (type in the middle, delete a range, paste-replace a chunk) — text must update normally with no glitches or cursor jumps.
3. Force-quit and relaunch the app, reopen the same note — body text must still match what was last typed (proves rehydration from `CRDTStore` works, not just the in-memory `text` state).
4. Delete the note — no crash (proves `CRDTStore.deleteAll` doesn't blow up on a real note).

Expected: all four checks pass with no visible regression versus the pre-Phase-2 editing experience.

- [ ] **Step 4: Commit**

```bash
git add morethantasks/morethantasks/Views/NoteView.swift
git commit -m "feat(crdt): route NoteDetailView's TextEditor through the CRDT body controller"
```

---

### Final: Full test suite run

- [ ] Run the complete test target once, per project test-cadence convention (single run at the end, not per task):

Run: `xcodebuild test -project morethantasks/morethantasks.xcodeproj -scheme morethantasks -destination 'platform=iOS Simulator,id=9014B4C3-C29C-4903-B52F-FFADF75D2F38'`
Expected: all tests PASS — Phase 1's `CharIDTests`, `RGADocumentTests`, `RGAConvergenceTests`, `RGAEditorTests`, `AuthTests`, `morethantasksTests`, plus this phase's `CRDTSiteTests`, `CRDTStoreTests`, `CRDTNoteBodyControllerTests`.

## Phase 2 done — definition of success

- `CRDTStore` persists the applied op log, outbox, and cursor for every note, keyed and isolated correctly, dedup-safe on replay.
- `CRDTNoteBodyController` rehydrates a note's `RGADocument` from `CRDTStore` on every construction and seeds it exactly once from the note's prior `body` text.
- Every note (new or pre-existing) has a CRDT op log the first time it's opened or created; deleting a note purges that log.
- `NoteDetailView`'s `TextEditor` is now backed by the CRDT — verified by the manual round-trip/relaunch/delete checks in Task 7.
- Nothing here talks to the network or the server; `notes.body`'s existing whole-note LWW sync path is untouched (the materialized CRDT text is what gets pushed through it, same as before).

**Next phase (separate plan, written after this lands):** Phase 3 — server schema migration (`note_crdt_ops`, `note_collaborators` in Postgres) and the two `crdt_ops` FastAPI endpoints, per the design spec Section 1 and Section 3.
