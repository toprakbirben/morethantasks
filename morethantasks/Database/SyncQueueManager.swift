//
//  SyncQueueManager.swift
//  morethantasks
//
//  Created by Toprak Birben on 01/06/2026.
//

import Foundation
import SQLite3

class SyncQueueManager {
    static let shared = SyncQueueManager()
    
    private var db: OpaquePointer?
    private let dataPath: String = "SyncQueue.sqlite"
    
    init() {
        db = openDatabase()
        createSyncQueueTable()
    }
    
    private func openDatabase() -> OpaquePointer? {
        let filePath = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(dataPath)
        
        var db: OpaquePointer? = nil
        if sqlite3_open(filePath.path, &db) != SQLITE_OK {
            debugPrint("Cannot open sync queue DB at \(filePath.path).")
            return nil
        } else {
            print("Sync queue DB successfully opened.")
            return db
        }
    }
    
    private func createSyncQueueTable() {
        let createTableString = """
        CREATE TABLE IF NOT EXISTS sync_queue (
            id TEXT PRIMARY KEY,
            operation_type TEXT NOT NULL,
            note_id TEXT NOT NULL,
            timestamp REAL NOT NULL,
            status TEXT NOT NULL,
            retry_count INTEGER NOT NULL,
            payload BLOB
        );
        """
        
        var createTableStatement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, createTableString, -1, &createTableStatement, nil) == SQLITE_OK {
            if sqlite3_step(createTableStatement) == SQLITE_DONE {
                print("Sync queue table created successfully.")
            } else {
                print("Sync queue table creation failed.")
            }
        } else {
            print("Sync queue table creation failed (prepare error).")
        }
        sqlite3_finalize(createTableStatement)
    }
    
    // MARK: - Queue Operations
    
    func enqueue(_ operation: SyncOperation) {
        let insertQuery = """
        INSERT OR REPLACE INTO sync_queue (id, operation_type, note_id, timestamp, status, retry_count, payload)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        
        var insertStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertQuery, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStatement, 1, (operation.id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (operation.operationType.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 3, (operation.noteId.uuidString as NSString).utf8String, -1, nil)
            sqlite3_bind_double(insertStatement, 4, operation.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(insertStatement, 5, (operation.status.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_int(insertStatement, 6, Int32(operation.retryCount))
            
            if let payload = operation.payload {
                payload.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(insertStatement, 7, bytes.baseAddress, Int32(payload.count), nil)
                }
            } else {
                sqlite3_bind_null(insertStatement, 7)
            }
            
            if sqlite3_step(insertStatement) == SQLITE_DONE {
                print("✅ Sync operation enqueued: \(operation.operationType) for note \(operation.noteId)")
            } else {
                print("❌ Failed to enqueue sync operation.")
            }
        }
        sqlite3_finalize(insertStatement)
    }
    
    func fetchPendingOperations() -> [SyncOperation] {
        var operations: [SyncOperation] = []
        let query = "SELECT * FROM sync_queue WHERE status = 'pending' ORDER BY timestamp ASC;"
        var queryStatement: OpaquePointer? = nil
        
        if sqlite3_prepare_v2(db, query, -1, &queryStatement, nil) == SQLITE_OK {
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let idString = String(cString: sqlite3_column_text(queryStatement, 0))
                guard let id = UUID(uuidString: idString) else { continue }
                
                let operationTypeString = String(cString: sqlite3_column_text(queryStatement, 1))
                guard let operationType = SyncOperationType(rawValue: operationTypeString) else { continue }
                
                let noteIdString = String(cString: sqlite3_column_text(queryStatement, 2))
                guard let noteId = UUID(uuidString: noteIdString) else { continue }
                
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 3))
                
                let statusString = String(cString: sqlite3_column_text(queryStatement, 4))
                guard let status = SyncStatus(rawValue: statusString) else { continue }
                
                let retryCount = Int(sqlite3_column_int(queryStatement, 5))
                
                var payload: Data? = nil
                if let blob = sqlite3_column_blob(queryStatement, 6) {
                    let size = sqlite3_column_bytes(queryStatement, 6)
                    payload = Data(bytes: blob, count: Int(size))
                }
                
                operations.append(SyncOperation(
                    id: id,
                    operationType: operationType,
                    noteId: noteId,
                    timestamp: timestamp,
                    status: status,
                    retryCount: retryCount,
                    payload: payload
                ))
            }
        }
        sqlite3_finalize(queryStatement)
        return operations
    }
    
    func updateOperationStatus(_ operationId: UUID, status: SyncStatus, retryCount: Int? = nil) {
        let updateQuery: String
        if let retryCount = retryCount {
            updateQuery = "UPDATE sync_queue SET status = ?, retry_count = ? WHERE id = ?;"
        } else {
            updateQuery = "UPDATE sync_queue SET status = ? WHERE id = ?;"
        }
        
        var updateStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateQuery, -1, &updateStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(updateStatement, 1, (status.rawValue as NSString).utf8String, -1, nil)
            
            if let retryCount = retryCount {
                sqlite3_bind_int(updateStatement, 2, Int32(retryCount))
                sqlite3_bind_text(updateStatement, 3, (operationId.uuidString as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_text(updateStatement, 2, (operationId.uuidString as NSString).utf8String, -1, nil)
            }
            
            if sqlite3_step(updateStatement) == SQLITE_DONE {
                print("✅ Operation status updated to \(status)")
            }
        }
        sqlite3_finalize(updateStatement)
    }
    
    func removeOperation(_ operationId: UUID) {
        let deleteQuery = "DELETE FROM sync_queue WHERE id = ?;"
        var deleteStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteQuery, -1, &deleteStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStatement, 1, (operationId.uuidString as NSString).utf8String, -1, nil)
            
            if sqlite3_step(deleteStatement) == SQLITE_DONE {
                print("✅ Operation removed from queue")
            }
        }
        sqlite3_finalize(deleteStatement)
    }
    
    func clearSyncedOperations() {
        let deleteQuery = "DELETE FROM sync_queue WHERE status = 'synced';"
        var deleteStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteQuery, -1, &deleteStatement, nil) == SQLITE_OK {
            if sqlite3_step(deleteStatement) == SQLITE_DONE {
                print("✅ Cleared synced operations")
            }
        }
        sqlite3_finalize(deleteStatement)
    }
    
    /// True if an operation for this note is still pending or in flight.
    /// Pull uses this to avoid clobbering a local change that hasn't round-tripped
    /// (and to avoid resurrecting a note whose delete hasn't been pushed yet).
    func hasPendingOperation(forNoteId noteId: UUID) -> Bool {
        let query = "SELECT COUNT(*) FROM sync_queue WHERE note_id = ? AND status IN ('pending', 'syncing');"
        var statement: OpaquePointer? = nil
        var count = 0
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (noteId.uuidString as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return count > 0
    }

    /// Drops the entire queue. Used on account deletion.
    func clearAll() {
        if sqlite3_exec(db, "DELETE FROM sync_queue;", nil, nil, nil) == SQLITE_OK {
            print("Cleared entire sync queue.")
        }
    }

    func getPendingOperationsCount() -> Int {
        let query = "SELECT COUNT(*) FROM sync_queue WHERE status = 'pending';"
        var queryStatement: OpaquePointer? = nil
        var count = 0
        
        if sqlite3_prepare_v2(db, query, -1, &queryStatement, nil) == SQLITE_OK {
            if sqlite3_step(queryStatement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(queryStatement, 0))
            }
        }
        sqlite3_finalize(queryStatement)
        return count
    }
}
