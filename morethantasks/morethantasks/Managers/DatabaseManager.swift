//
//  DatabaseManager.swift
//  morethantasks
//
//  Created by Toprak Birben on 22/09/2025.
//
//  Offline-first orchestrator. SQLite is the single source of truth: every read
//  and write hits it first and the UI updates instantly. Changes are enqueued in
//  a persistent outbox (SyncQueueManager) and pushed/pulled by SyncEngine when
//  online. Postgres is never read for UI.
//

import Foundation
import Combine
import Network

@MainActor
class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()

    private let sqlite = SQLiteDatabase()
    private let postgres = PostgresDatabase()
    private let syncQueue = SyncQueueManager.shared
    private lazy var engine = SyncEngine(sqlite: sqlite, postgres: postgres, syncQueue: syncQueue)

    @Published var isConnected: Bool = false
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    @Published var pendingSyncCount: Int = 0

    @Published var tagsArray: [String] = []
    @Published var notesArray: [Notes] = []

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitorQueue")
    private var periodicTask: Task<Void, Never>?
    private let syncInterval: TimeInterval = 30

    private var currentUserId: Int { UserDefaults.standard.integer(forKey: "loggedInUserId") }

    init() {
        loadLocalData()
        setupNetworkMonitoring()
        startPeriodicSync()
    }

    deinit {
        monitor.cancel()
        periodicTask?.cancel()
    }

    // MARK: - Network monitoring

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied
                // Sync as soon as we regain connectivity.
                if !wasConnected && self.isConnected {
                    await self.triggerSync()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func startPeriodicSync() {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.syncInterval ?? 30
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self = self else { return }
                if self.isConnected { await self.triggerSync() }
            }
        }
    }

    // MARK: - Local data

    func loadLocalData() {
        notesArray = sqlite.fetchNotes(forUser: currentUserId)
        rebuildTags()
        pendingSyncCount = syncQueue.getPendingOperationsCount()
    }

    /// Kept for existing call sites; reads stay local.
    func fetchNotes() { loadLocalData() }
    func fetchTags() { rebuildTags() }

    func getTags() -> [String] { tagsArray.sorted() }

    // MARK: - CRUD (local first, then enqueue for sync)

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

    func update(note: Notes) {
        var stamped = note
        stamped.userID = currentUserId
        stamped.lastUpdated = Date()

        sqlite.update(
            noteId: stamped.id.uuidString,
            title: stamped.title,
            noteBody: stamped.body,
            noteParent: stamped.parentId?.uuidString,
            noteColor: stamped.colorHex,
            tag: stamped.tag
        ) {
            Task { @MainActor in
                if let index = self.notesArray.firstIndex(where: { $0.id == stamped.id }) {
                    self.notesArray[index] = stamped
                }
                self.rebuildTags()
                self.enqueue(.update, note: stamped)
            }
        }
    }

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

    // MARK: - Sync lifecycle

    /// Call after a successful login: refresh local view and seed SQLite from
    /// the server so an existing user never sees an empty app.
    func userDidLogin() {
        loadLocalData()
        Task { await triggerSync() }
    }

    /// Call on account deletion to purge this user's local data and pending ops.
    func purgeLocalData(forUser userId: Int) {
        sqlite.deleteAllNotes(forUser: userId)
        syncQueue.clearAll()
        notesArray = []
        tagsArray = []
        pendingSyncCount = 0
    }

    func forceSyncNow() async {
        await triggerSync()
    }

    private func triggerSync() async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        await engine.sync(currentUserId: currentUserId)
        isSyncing = false
        lastSyncDate = Date()
        loadLocalData()   // reflect anything pulled + refresh pending count
    }

    // MARK: - Helpers

    private func enqueue(_ type: SyncOperationType, note: Notes) {
        let payload = NotePayload(
            id: note.id, title: note.title, body: note.body, parentId: note.parentId,
            lastUpdated: note.lastUpdated, userID: note.userID, colorHex: note.colorHex, tag: note.tag
        )
        let data = try? JSONEncoder().encode(payload)
        syncQueue.enqueue(SyncOperation(operationType: type, noteId: note.id, payload: data))
        pendingSyncCount = syncQueue.getPendingOperationsCount()
        if isConnected { Task { await triggerSync() } }
    }

    private func enqueueDelete(_ noteId: UUID) {
        syncQueue.enqueue(SyncOperation(operationType: .delete, noteId: noteId, payload: nil))
        pendingSyncCount = syncQueue.getPendingOperationsCount()
        if isConnected { Task { await triggerSync() } }
    }

    private func rebuildTags() {
        let tagsSet = Set(
            notesArray.compactMap { note -> String? in
                let trimmed = note.tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        )
        tagsArray = Array(tagsSet).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
