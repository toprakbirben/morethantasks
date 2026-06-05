//
//  SQLiteDatabase.swift
//  morethantasks
//
//  Created by Toprak Birben on 22/09/2025.
//
//  Local source of truth. All UI reads come from here. Writes happen here
//  first, then get enqueued for sync (see SyncQueueManager / SyncEngine).
//

import SQLite3
import Foundation

class SQLiteDatabase {
    let dataPath: String = "MyDB.sqlite"
    var db: OpaquePointer?

    init() {
        db = openDatabase()
        createNotesTable()
    }

    private func openDatabase() -> OpaquePointer? {
        let filePath = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(dataPath)

        var db: OpaquePointer? = nil
        if sqlite3_open(filePath.path, &db) != SQLITE_OK {
            debugPrint("Cannot open DB at \(filePath.path).")
            return nil
        } else {
            return db
        }
    }

    private func createNotesTable() {
        let createTableString = """
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            parent_id TEXT,
            last_updated REAL NOT NULL,
            created_by_user_id INT NOT NULL,
            color TEXT,
            tag TEXT
        );
        """

        var createTableStatement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, createTableString, -1, &createTableStatement, nil) == SQLITE_OK {
            if sqlite3_step(createTableStatement) == SQLITE_DONE {
                print("Notes table ready.")
            } else {
                print("Notes table creation failed.")
            }
        } else {
            print("Notes table creation failed (prepare error).")
        }
        sqlite3_finalize(createTableStatement)
    }

    // MARK: - Fetch (scoped to the logged-in user)

    func fetchNotes(forUser userId: Int) -> [Notes] {
        var notes: [Notes] = []
        let query = "SELECT id, title, body, parent_id, last_updated, created_by_user_id, color, tag FROM notes WHERE created_by_user_id = ?;"
        var queryStatement: OpaquePointer? = nil

        if sqlite3_prepare_v2(db, query, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(queryStatement, 1, Int32(userId))
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let idString = String(cString: sqlite3_column_text(queryStatement, 0))
                guard let id = UUID(uuidString: idString) else { continue }

                let title = String(cString: sqlite3_column_text(queryStatement, 1))
                let body = String(cString: sqlite3_column_text(queryStatement, 2))

                var parentId: UUID? = nil
                if let parentIdC = sqlite3_column_text(queryStatement, 3) {
                    parentId = UUID(uuidString: String(cString: parentIdC))
                }

                let lastUpdated = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 4))
                let createdByUserId = Int(sqlite3_column_int(queryStatement, 5))
                let color = sqlite3_column_text(queryStatement, 6).map { String(cString: $0) }
                let tag = sqlite3_column_text(queryStatement, 7).map { String(cString: $0) }

                notes.append(Notes(
                    id: id,
                    title: title,
                    body: body,
                    parentId: parentId,
                    children: [],
                    lastUpdated: lastUpdated,
                    userID: createdByUserId,
                    colorHex: color,
                    tag: tag
                ))
            }
        } else {
            print("Failed to prepare fetch query.")
        }
        sqlite3_finalize(queryStatement)
        return notes
    }

    func fetchTags(forUser userId: Int) -> [String] {
        var tags: [String] = []
        let query = "SELECT DISTINCT tag FROM notes WHERE created_by_user_id = ? AND tag IS NOT NULL AND tag <> '';"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(userId))
            while sqlite3_step(statement) == SQLITE_ROW {
                let tag = String(cString: sqlite3_column_text(statement, 0))
                tags.append(tag)
            }
        }
        sqlite3_finalize(statement)
        return tags
    }

    // MARK: - Insert / Upsert
    //
    // INSERT OR REPLACE so this also serves as the upsert used when pulling
    // server rows into the local store. The note's own id/userID/tag are
    // persisted verbatim — the client-generated id is the shared key across
    // SQLite and Postgres, which is what makes sync correct.

    func insert(_ note: Notes, completion: @escaping () -> Void) {
        let insertQuery = """
        INSERT OR REPLACE INTO notes (id, title, body, parent_id, last_updated, created_by_user_id, color, tag)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var insertStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertQuery, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStatement, 1, (note.id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (note.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 3, (note.body as NSString).utf8String, -1, nil)
            if let parentId = note.parentId {
                sqlite3_bind_text(insertStatement, 4, (parentId.uuidString as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(insertStatement, 4)
            }
            sqlite3_bind_double(insertStatement, 5, note.lastUpdated.timeIntervalSince1970)
            sqlite3_bind_int(insertStatement, 6, Int32(note.userID))
            if let color = note.colorHex {
                sqlite3_bind_text(insertStatement, 7, (color as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(insertStatement, 7)
            }
            sqlite3_bind_text(insertStatement, 8, ((note.tag ?? "") as NSString).utf8String, -1, nil)

            if sqlite3_step(insertStatement) == SQLITE_DONE {
                DispatchQueue.main.async { completion() }
            } else {
                print("Failed to insert note into SQLite.")
            }
        } else {
            print("Failed to prepare insert statement.")
        }
        sqlite3_finalize(insertStatement)
    }

    // MARK: - Update (partial, for local edits)

    func update(noteId: String, title: String?, noteBody: String?, noteParent: String?, noteColor: String?, tag: String?, completion: @escaping () -> Void) {
        let updateQuery = """
        UPDATE notes
        SET title = COALESCE(?, title),
            body = COALESCE(?, body),
            parent_id = ?,
            color = COALESCE(?, color),
            tag = COALESCE(?, tag),
            last_updated = ?
        WHERE id = ?;
        """

        var updateStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateQuery, -1, &updateStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(updateStatement, 1, title != nil ? (title! as NSString).utf8String : nil, -1, nil)
            sqlite3_bind_text(updateStatement, 2, noteBody != nil ? (noteBody! as NSString).utf8String : nil, -1, nil)
            sqlite3_bind_text(updateStatement, 3, noteParent != nil ? (noteParent! as NSString).utf8String : nil, -1, nil)
            sqlite3_bind_text(updateStatement, 4, noteColor != nil ? (noteColor! as NSString).utf8String : nil, -1, nil)
            sqlite3_bind_text(updateStatement, 5, tag != nil ? (tag! as NSString).utf8String : nil, -1, nil)
            sqlite3_bind_double(updateStatement, 6, Date().timeIntervalSince1970)
            sqlite3_bind_text(updateStatement, 7, (noteId as NSString).utf8String, -1, nil)

            if sqlite3_step(updateStatement) == SQLITE_DONE {
                DispatchQueue.main.async { completion() }
            } else {
                print("Failed to update note.")
            }
        } else {
            print("Failed to prepare update statement.")
        }
        sqlite3_finalize(updateStatement)
    }

    // MARK: - Delete (hard delete; tombstone lives server-side)

    func delete(noteId: UUID, completion: @escaping () -> Void) {
        let deleteQuery = "DELETE FROM notes WHERE id = ?;"
        var deleteStatement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteQuery, -1, &deleteStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStatement, 1, (noteId.uuidString as NSString).utf8String, -1, nil)

            if sqlite3_step(deleteStatement) == SQLITE_DONE {
                DispatchQueue.main.async { completion() }
            } else {
                print("Failed to delete note.")
            }
        } else {
            print("Failed to prepare delete statement.")
        }
        sqlite3_finalize(deleteStatement)
    }

    /// Used on account deletion to purge all of a user's local notes.
    func deleteAllNotes(forUser userId: Int) {
        let deleteQuery = "DELETE FROM notes WHERE created_by_user_id = ?;"
        var deleteStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteQuery, -1, &deleteStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(deleteStatement, 1, Int32(userId))
            if sqlite3_step(deleteStatement) == SQLITE_DONE {
                print("Purged local notes for user \(userId).")
            }
        }
        sqlite3_finalize(deleteStatement)
    }
}
