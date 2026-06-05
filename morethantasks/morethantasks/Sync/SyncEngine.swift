//
//  SyncEngine.swift
//  morethantasks
//
//  Created by Toprak Birben on 01/06/2026.
//
//  Push/pull orchestration. Owned by DatabaseManager (not a singleton) so there
//  is exactly one set of sqlite/postgres/queue instances and one connectivity
//  signal. Push drains the outbox to the server; pull reconciles server state
//  back into the local store. A sync pass is always push-then-pull.
//

import Foundation

enum SyncError: Error {
    case invalidPayload
}

@MainActor
class SyncEngine {
    private let sqlite: SQLiteDatabase
    private let postgres: PostgresDatabase
    private let syncQueue: SyncQueueManager

    private let maxRetries = 3

    init(sqlite: SQLiteDatabase, postgres: PostgresDatabase, syncQueue: SyncQueueManager) {
        self.sqlite = sqlite
        self.postgres = postgres
        self.syncQueue = syncQueue
    }

    /// One full sync pass. Caller guarantees connectivity and supplies the
    /// current user id (pull is scoped and skipped when id is invalid).
    func sync(currentUserId: Int) async {
        await pushLocalChanges()
        await pullRemoteChanges(currentUserId: currentUserId)
    }

    // MARK: - Push (outbox → server)

    private func pushLocalChanges() async {
        let pendingOps = syncQueue.fetchPendingOperations()
        guard !pendingOps.isEmpty else { return }

        for operation in pendingOps {
            syncQueue.updateOperationStatus(operation.id, status: .syncing)

            let succeeded = await perform(operation)

            if succeeded {
                syncQueue.removeOperation(operation.id)
            } else {
                let newRetryCount = operation.retryCount + 1
                if newRetryCount >= maxRetries {
                    syncQueue.updateOperationStatus(operation.id, status: .failed, retryCount: newRetryCount)
                } else {
                    // back to pending so the next pass retries it
                    syncQueue.updateOperationStatus(operation.id, status: .pending, retryCount: newRetryCount)
                }
            }
        }
    }

    private func perform(_ operation: SyncOperation) async -> Bool {
        switch operation.operationType {
        case .insert, .update:
            guard let payload = operation.payload,
                  let note = try? decodeNote(payload) else { return false }
            return operation.operationType == .insert
                ? await pushInsert(note)
                : await pushUpdate(note)
        case .delete:
            return await pushDelete(operation.noteId)
        }
    }

    private func decodeNote(_ payload: Data) throws -> Notes {
        let p = try JSONDecoder().decode(NotePayload.self, from: payload)
        return Notes(
            id: p.id, title: p.title, body: p.body, parentId: p.parentId,
            children: [], lastUpdated: p.lastUpdated, userID: p.userID,
            colorHex: p.colorHex, tag: p.tag
        )
    }

    private func pushInsert(_ note: Notes) async -> Bool {
        do { try await postgres.insert(note); return true }
        catch { print("Postgres insert failed:", error); return false }
    }

    private func pushUpdate(_ note: Notes) async -> Bool {
        do {
            try await postgres.update(
                noteId: note.id.uuidString, title: note.title, noteBody: note.body,
                noteParent: note.parentId?.uuidString, noteColor: note.colorHex, tag: note.tag
            )
            return true
        } catch { print("Postgres update failed:", error); return false }
    }

    private func pushDelete(_ noteId: UUID) async -> Bool {
        do { try await postgres.delete(noteId: noteId); return true }
        catch { print("Postgres delete failed:", error); return false }
    }

    // MARK: - Pull (server → local)

    private func pullRemoteChanges(currentUserId: Int) async {
        // Never reconcile with an empty/unknown user scope — that would let a
        // zero-result fetch delete the whole local store.
        guard currentUserId > 0 else { return }

        let (remoteActive, remoteDeletedIds) = await fetchRemote(forUser: currentUserId)
        let localNotes = sqlite.fetchNotes(forUser: currentUserId)
        let localById = Dictionary(localNotes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Upsert remote-active notes that are new or strictly newer.
        for remote in remoteActive {
            // Skip anything with a local change still in flight (avoids the
            // server echo clobbering a fresh local edit).
            if syncQueue.hasPendingOperation(forNoteId: remote.id) { continue }

            if let local = localById[remote.id] {
                if remote.lastUpdated > local.lastUpdated {
                    await upsertLocal(remote)
                }
            } else {
                await upsertLocal(remote)
            }
        }

        // Apply server tombstones — but never a note whose own delete (or any op)
        // hasn't pushed yet, and only if we actually have it locally.
        for id in remoteDeletedIds {
            if syncQueue.hasPendingOperation(forNoteId: id) { continue }
            if localById[id] != nil {
                await deleteLocal(id)
            }
        }
    }

    /// Runs the BLOCKING Postgres read off the main thread, then returns to the
    /// main actor with the result.
    private func fetchRemote(forUser userId: Int) async -> (active: [Notes], deletedIds: [UUID]) {
        let pg = postgres
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: pg.fetchNotesForSync(forUser: userId))
            }
        }
    }

    private func upsertLocal(_ note: Notes) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sqlite.insert(note) { cont.resume() }
        }
    }

    private func deleteLocal(_ noteId: UUID) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sqlite.delete(noteId: noteId) { cont.resume() }
        }
    }
}
