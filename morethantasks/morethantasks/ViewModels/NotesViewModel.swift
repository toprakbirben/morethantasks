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
}
