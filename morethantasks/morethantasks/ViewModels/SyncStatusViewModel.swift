//
//  SyncStatusViewModel.swift
//  morethantasks
//

import Foundation
import Combine

@MainActor
final class SyncStatusViewModel: ObservableObject {
    private let store: DatabaseManager
    private var cancellables = Set<AnyCancellable>()

    init(store: DatabaseManager? = nil) {
        let store = store ?? .shared
        self.store = store
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var isConnected: Bool { store.isConnected }
    var isSyncing: Bool { store.isSyncing }
    var pendingSyncCount: Int { store.pendingSyncCount }
    var canSync: Bool { !store.isSyncing && store.isConnected }

    func sync() async { await store.forceSyncNow() }

    var lastSyncText: String? {
        guard let date = store.lastSyncDate else { return nil }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
}
