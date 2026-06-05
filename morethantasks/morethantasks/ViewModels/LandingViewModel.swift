//
//  LandingViewModel.swift
//  morethantasks
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class LandingViewModel: ObservableObject {
    private let store: DatabaseManager
    private let reminderStore: ReminderManager
    private var cancellables = Set<AnyCancellable>()

    init(store: DatabaseManager? = nil, reminderStore: ReminderManager? = nil) {
        let store = store ?? .shared
        let reminderStore = reminderStore ?? .shared
        self.store = store
        self.reminderStore = reminderStore
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        reminderStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var notes: [Notes] { store.notesArray }
    var tags: [String] { store.tagsArray }

    func filteredNotes(searchText: String) -> [Notes] {
        Helper.shared.filteredNotes(searchText: searchText, notes: store.notesArray)
    }

    /// Writable binding so the reminders list can toggle completion in place.
    var reminders: Binding<[Reminder]> {
        Binding(
            get: { [reminderStore] in reminderStore.remindersArray },
            set: { [reminderStore] newValue in reminderStore.remindersArray = newValue }
        )
    }

    func update(_ note: Notes) { store.update(note: note) }
}
