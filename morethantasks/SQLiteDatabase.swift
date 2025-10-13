//
//  SQLiteDatabase.swift
//  morethantasks
//
//  Created by Toprak Birben on 22/09/2025.
//

import SQLite3
import Foundation

class SQLiteDatabase: DatabaseProvider {
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
            print("DB successfully opened at \(filePath.path).")
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
            created_by_user_id TEXT NOT NULL,
            color TEXT,
            tag TEXT
        );
        """

        var createTableStatement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, createTableString, -1, &createTableStatement, nil) == SQLITE_OK {
            if sqlite3_step(createTableStatement) == SQLITE_DONE {
                print("Notes table created successfully.")
            } else {
                print("Notes table creation failed.")
            }
        } else {
            print("Notes table creation failed (prepare error).")
        }
        sqlite3_finalize(createTableStatement)
    }
    
    // MARK: - Fetch
    func fetchNotes() -> [Notes] {
        var notes: [Notes] = []
        let query = "SELECT * FROM notes"
        var queryStatement: OpaquePointer? = nil
        
        if sqlite3_prepare_v2(db, query, -1, &queryStatement, nil) == SQLITE_OK {
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
                let createdByUserId = String(cString: sqlite3_column_text(queryStatement, 5))
                let color = sqlite3_column_text(queryStatement, 6).map { String(cString: $0) }
                let tag = sqlite3_column_text(queryStatement, 7).map { String(cString: $0) }

                notes.append(Notes(
                    id: id,
                    title: title,
                    body: body,
                    parentId: parentId,
                    children: [],
                    lastUpdated: lastUpdated,
                    createdByUserId: createdByUserId,
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
    
    func fetchTags() -> [String] {
        var tags: [String] = []
        let query = "SELECT DISTINCT tag FROM notes WHERE tag IS NOT NULL AND tag <> '';"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let tag = String(cString: sqlite3_column_text(statement, 0))
                tags.append(tag)
            }
        }
        sqlite3_finalize(statement)
        return tags
    }
    
    // MARK: - Insert
    func insert(title: String, noteBody: String,tag: String?, completion: @escaping () -> Void) {
        let noteId = UUID().uuidString
        let lastUpdated = Date().timeIntervalSince1970
        let insertQuery = """
        INSERT INTO notes (id, title, body, parent_id, last_updated, created_by_user_id, color, tag)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var insertStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertQuery, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStatement, 1, (noteId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 3, (noteBody as NSString).utf8String, -1, nil)
            sqlite3_bind_null(insertStatement, 4) // parent_id optional
            sqlite3_bind_double(insertStatement, 5, lastUpdated)
            sqlite3_bind_text(insertStatement, 6, ("toprak" as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 7, ("#28A745" as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 8, ("" as NSString).utf8String, -1, nil)

            if sqlite3_step(insertStatement) == SQLITE_DONE {
                print("Note inserted successfully into SQLite.")
                DispatchQueue.main.async { completion() }
            } else {
                print("Failed to insert note.")
            }
        } else {
            print("Failed to prepare insert statement.")
        }
        sqlite3_finalize(insertStatement)
    }
    
    // MARK: - Update
    func update(noteId: String, title: String?, noteBody: String?, noteParent: String?, noteColor: String?, tag: String?, completion: @escaping () -> Void) {
        
        let updateQuery = """
        UPDATE notes
        SET title = COALESCE(?, title),
            body = COALESCE(?, body),
            parent_id = COALESCE(?, parent_id),
            color = COALESCE(?, color),
            last_updated = ?
        WHERE id = ?;
        """
        
        var updateStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateQuery, -1, &updateStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(updateStatement, 1, title != nil ? (title! as NSString).utf8String : nil, -1, nil)
            sqlite3_bind_text(updateStatement, 2, noteBody != nil ? (noteBody! as NSString).utf8String : nil, -1, nil)
            sqlite3_bind_text(updateStatement, 3, noteParent != nil ? (noteParent! as NSString).utf8String : nil, -1, nil)
            sqlite3_bind_text(updateStatement, 4, noteColor != nil ? (noteColor! as NSString).utf8String : nil, -1, nil)
            sqlite3_bind_double(updateStatement, 5, Date().timeIntervalSince1970)
            sqlite3_bind_text(updateStatement, 6, (noteId as NSString).utf8String, -1, nil)
            
            if sqlite3_step(updateStatement) == SQLITE_DONE {
                print("Note updated successfully.")
                DispatchQueue.main.async { completion() }
            } else {
                print("Failed to update note.")
            }
        } else {
            print("Failed to prepare update statement.")
        }
        sqlite3_finalize(updateStatement)
    }
    
    // MARK: - Delete
    func delete(noteId: UUID, completion: @escaping () -> Void) {
        let deleteQuery = "DELETE FROM notes WHERE id = ?;"
        var deleteStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteQuery, -1, &deleteStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStatement, 1, (noteId.uuidString as NSString).utf8String, -1, nil)
            
            if sqlite3_step(deleteStatement) == SQLITE_DONE {
                print("Note deleted successfully.")
                DispatchQueue.main.async { completion() }
            } else {
                print("Failed to delete note.")
            }
        } else {
            print("Failed to prepare delete statement.")
        }
        sqlite3_finalize(deleteStatement)
    }
}
