//
//  NotesViewModel.swift
//  morethantasks
//
//  Wraps the offline-first DatabaseManager store so Views bind to a ViewModel
//  instead of calling the store directly. Re-publishes the store's changes so
//  SwiftUI updates when notes/tags change underneath.
//

import Foundation
import Combine

@MainActor
final class NotesViewModel: ObservableObject {
    private let store: DatabaseManager
    private var cancellables = Set<AnyCancellable>()

    init(store: DatabaseManager? = nil) {
        let store = store ?? .shared
        self.store = store
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var notes: [Notes] { store.notesArray }
    var tags: [String] { store.tagsArray }
    func getTags() -> [String] { store.getTags() }

    func add(_ note: Notes) { store.insert(note: note) }
    func update(_ note: Notes) { store.update(note: note) }
    func delete(id: UUID) { store.delete(noteId: id) }

    // MARK: - Hierarchy

    /// Normalizes a note's tag the way the list sections group on: empty/blank → "None".
    private func tagKey(for note: Notes) -> String {
        let trimmed = note.tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "None" : trimmed
    }

    /// Root notes for a tag section, each with `children` populated recursively.
    /// A note whose parentId is nil OR points to a missing note is treated as a
    /// root, so an orphan never disappears from the tree.
    func rootNotes(forTag tag: String) -> [Notes] {
        let all = notes
        let ids = Set(all.map(\.id))
        var byParent: [UUID: [Notes]] = [:]
        for note in all {
            if let pid = note.parentId, ids.contains(pid) {
                byParent[pid, default: []].append(note)
            }
        }
        func attach(_ node: Notes) -> Notes {
            var copy = node
            copy.children = (byParent[node.id] ?? []).map(attach)
            return copy
        }
        return all
            .filter { ($0.parentId == nil || !ids.contains($0.parentId!)) && tagKey(for: $0) == tag }
            .map(attach)
    }

    /// All descendant ids of a note — used to prevent cycles when re-parenting.
    func descendantIds(of id: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var stack = [id]
        while let current = stack.popLast() {
            for child in notes where child.parentId == current {
                if result.insert(child.id).inserted { stack.append(child.id) }
            }
        }
        return result
    }

    /// Deletes a note, promoting its direct children up to the deleted note's
    /// own parent (or to root if it was top-level) and clearing their tag.
    func deleteAndPromoteChildren(_ note: Notes) {
        let newParent = note.parentId
        for child in notes where child.parentId == note.id {
            var promoted = child
            promoted.parentId = newParent
            promoted.tag = ""
            update(promoted)
        }
        delete(id: note.id)
    }

    /// Renames a tag server-side (propagating to anyone it's shared with,
    /// see routers/tags.py's PATCH by owner+name) and updates this device's
    /// own root notes to match -- only root notes carry a tag string.
    func renameTag(_ oldName: String, to newName: String, tagSharing: TagSharingService? = nil) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        do {
            try await (tagSharing ?? .shared).rename(tagName: oldName, to: trimmed)
            for note in notes where (note.tag ?? "") == oldName {
                var updated = note
                updated.tag = trimmed
                update(updated)
            }
        } catch {
            // Non-fatal: matches the rest of this ViewModel's tag editing,
            // which doesn't surface a dedicated error UI either.
        }
    }
}
