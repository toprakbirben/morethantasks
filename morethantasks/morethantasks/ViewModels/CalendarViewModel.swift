//
//  CalendarViewModel.swift
//  morethantasks
//

import Foundation
import Combine

@MainActor
final class CalendarViewModel: ObservableObject {
    private let store: DatabaseManager
    private let eventStore: EventManager
    private var cancellables = Set<AnyCancellable>()

    init(store: DatabaseManager? = nil, eventStore: EventManager? = nil) {
        let store = store ?? .shared
        let eventStore = eventStore ?? .shared
        self.store = store
        self.eventStore = eventStore
        eventStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var events: [Event] { eventStore.eventList }

    /// Rebuild calendar events from the current notes (notes with a @DD-MM-YYYY
    /// marker become all-day events).
    func refreshEvents() {
        eventStore.createEvents(notes: store.notesArray)
    }
}
