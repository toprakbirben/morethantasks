//  CRDTSyncEngine.swift
//  Poll-while-open + debounced push (Section 3 of the design spec). Owned by
//  the view for one open note's lifetime: start() on appear, stop() on
//  disappear. Independent of the whole-note SyncEngine — this is the
//  op-granular channel for `body` only.
import Foundation

@MainActor
final class CRDTSyncEngine {
    private let noteId: UUID
    private let controller: CRDTNoteBodyController
    private let store: CRDTStore
    private let client: CRDTSyncClient

    private var pollTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?

    private let pollInterval: TimeInterval
    private let pushDebounce: TimeInterval

    private var requesterId: Int { UserDefaults.standard.integer(forKey: "loggedInUserId") }

    /// Fired on the main actor with the freshly-merged text whenever a pull
    /// brings in ops from another site. The view sets this to push pulled
    /// changes into its own `text` binding — without it, a collaborator's
    /// edits land in the document/store but never reach the screen until the
    /// user types something themselves.
    var onRemoteTextChange: ((String) -> Void)?

    init(
        noteId: UUID,
        controller: CRDTNoteBodyController,
        store: CRDTStore = .shared,
        client: CRDTSyncClient = .shared,
        pollInterval: TimeInterval = 2.5,
        pushDebounce: TimeInterval = 1.0
    ) {
        self.noteId = noteId
        self.controller = controller
        self.store = store
        self.client = client
        self.pollInterval = pollInterval
        self.pushDebounce = pushDebounce
    }

    /// Starts the ~2-3s poll loop. Call when the note is opened.
    func start() {
        stop()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pullOnce()
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
            }
        }
    }

    /// Stops polling and cancels any pending debounced push. Call when the
    /// note is closed; any outbox ops are picked up on the next open (or by a
    /// future background push) rather than lost.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        pushTask?.cancel()
        pushTask = nil
    }

    /// Call after every local edit. Debounces so rapid typing coalesces into
    /// one push ~1s after the user pauses, instead of one push per keystroke.
    func scheduleLocalPush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.pushDebounce * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.pushOnce()
        }
    }

    private func pullOnce() async {
        guard requesterId > 0 else { return }
        let cursor = store.cursor(forNote: noteId)
        do {
            let (ops, latestSeq) = try await client.pull(noteId: noteId, since: cursor, requesterId: requesterId)
            if !ops.isEmpty {
                let materialized = controller.applyRemoteOps(ops)
                onRemoteTextChange?(materialized)
            }
            // Advance the cursor only after ops are durably applied locally
            // (Section 5: "cursor integrity") — applyRemoteOps writes to
            // CRDTStore synchronously above, so this ordering already holds.
            if latestSeq != cursor {
                store.setCursor(forNote: noteId, serverSeq: latestSeq)
            }
        } catch {
            print("CRDTSyncEngine: pull failed for note \(noteId):", error)
        }
    }

    private func pushOnce() async {
        guard requesterId > 0 else { return }
        let outbox = store.fetchOutboxOps(forNote: noteId)
        guard !outbox.isEmpty else { return }
        do {
            try await client.push(ops: outbox, noteId: noteId, materializedBody: controller.materializedText, requesterId: requesterId)
            store.removeFromOutbox(outbox, noteId: noteId)
        } catch {
            print("CRDTSyncEngine: push failed for note \(noteId):", error)
        }
    }
}
