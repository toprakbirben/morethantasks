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
            if !seedOps.isEmpty { store.appendLocalOps(seedOps, noteId: noteId) }
        }
    }

    var materializedText: String { document.text() }

    @discardableResult
    func applyLocalChange(from old: String, to new: String) -> String {
        let ops = editor.applyLocalChange(from: old, to: new)
        if !ops.isEmpty { store.appendLocalOps(ops, noteId: noteId) }
        return document.text()
    }

    /// Merges ops pulled from the server (Section 3's poll loop) into the
    /// in-memory document and the applied log. Never touches the outbox —
    /// these ops didn't originate locally.
    @discardableResult
    func applyRemoteOps(_ ops: [RGAOp]) -> String {
        guard !ops.isEmpty else { return document.text() }
        for op in ops { document.apply(op) }
        store.applyRemoteOps(ops, noteId: noteId)
        return document.text()
    }
}
