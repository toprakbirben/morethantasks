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
