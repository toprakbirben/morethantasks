//
//  SyncOperation.swift
//  morethantasks
//
//  Created by Toprak Birben on 01/06/2026.
//

import Foundation

enum SyncOperationType: String, Codable {
    case insert
    case update
    case delete
}

enum SyncStatus: String, Codable {
    case pending
    case syncing
    case synced
    case failed
}

struct SyncOperation: Identifiable, Codable {
    let id: UUID
    let operationType: SyncOperationType
    let noteId: UUID
    let timestamp: Date
    var status: SyncStatus
    var retryCount: Int
    let payload: Data? // JSON encoded note data
    
    init(
        id: UUID = UUID(),
        operationType: SyncOperationType,
        noteId: UUID,
        timestamp: Date = Date(),
        status: SyncStatus = .pending,
        retryCount: Int = 0,
        payload: Data? = nil
    ) {
        self.id = id
        self.operationType = operationType
        self.noteId = noteId
        self.timestamp = timestamp
        self.status = status
        self.retryCount = retryCount
        self.payload = payload
    }
}

// Model for storing notes data in sync queue
struct NotePayload: Codable {
    let id: UUID
    let title: String
    let body: String
    let parentId: UUID?
    let lastUpdated: Date
    let userID: Int
    let colorHex: String?
    let tag: String?
}
