//
//  DatabaseManager.swift
//  morethantasks
//
//  Created by Toprak Birben on 22/09/2025.
//

import Foundation
import PostgresClientKit
import Combine
import Network

protocol DatabaseProvider {
    func fetchNotes() -> [Notes]
    func fetchTags() -> [String]
    func insert(title: String, noteBody: String, tag: String?, completion: @escaping () -> Void)
    func update(noteId: String, title: String?, noteBody: String?, noteParent: String?, noteColor: String?,tag: String?, completion: @escaping () -> Void)
    func delete(noteId: UUID, completion: @escaping () -> Void)
}

@MainActor
class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    
    private let postgres = PostgresDatabase()
    private let sqlite = SQLiteDatabase()
    
    @Published private(set) var activeDatabase: DatabaseProvider
    @Published var isConnected: Bool = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitorQueue")
    
    @Published var tagsArray: [String] = []
    @Published var notesArray: [Notes] = []


    
    init() {
        self.activeDatabase = sqlite
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }
                self.isConnected = path.status == .satisfied
                self.activeDatabase = self.isConnected ? self.postgres : self.sqlite
                //self.activeDatabase = self.sqlite // DEBUG PURPOSES
                self.fetchNotes()
                self.fetchTags()
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
    
    func syncNotes() {
        
    }
    
    func fetchNotes() {
        notesArray = activeDatabase.fetchNotes()
    }
    
    func fetchTags() {
        tagsArray = activeDatabase.fetchTags()
    }
    
    func insert(note: Notes) {
        if !notesArray.contains(where: { $0.id == note.id }) {
                activeDatabase.insert(title: note.title, noteBody: note.body, tag: note.tag) {
                    Task { @MainActor in
                        var updatedNotes = self.notesArray
                        updatedNotes.append(note)
                        self.notesArray = updatedNotes

                        let tagsSet = Set(
                            self.notesArray.map { note in
                                let trimmed = note.tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                return trimmed.isEmpty ? "None" : trimmed
                            }
                        )
                        self.tagsArray = Array(tagsSet)
                    }
                }
            }
    }
    
    func update(note: Notes) {
        activeDatabase.update(
            noteId: note.id.uuidString,
            title: note.title,
            noteBody: note.body,
            noteParent: note.parentId?.uuidString,
            noteColor: note.colorHex,
            tag: note.tag
        ) {
            Task { @MainActor in
                if let index = self.notesArray.firstIndex(where: { $0.id == note.id }) {
                    var updatedNotes = self.notesArray
                    updatedNotes[index] = note
                    self.notesArray = updatedNotes
                    print("Update success for note \(note.id)")
                }
                let tagsSet = Set(
                    self.notesArray.map { note in
                        let trimmed = note.tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return trimmed.isEmpty ? "None" : trimmed
                    }
                )
                let sortedTags = Array(tagsSet).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                self.tagsArray = sortedTags
            }
        }
    }
    
    func delete(noteId: UUID) {
        activeDatabase.delete(noteId: noteId) {
            Task { @MainActor in
                var updatedNotes = self.notesArray
                updatedNotes.removeAll { $0.id == noteId }
                self.notesArray = updatedNotes
                let tagsSet = Set(
                    self.notesArray.map { note in
                        let trimmed = note.tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return trimmed.isEmpty ? "None" : trimmed
                    }
                )
                // Optional: make “None” appear first
                let sortedTags = Array(tagsSet).sorted { a, b in
                    if a == "None" { return true }
                    if b == "None" { return false }
                    return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                }
                self.tagsArray = sortedTags

            }
        }
    }
    
    func getTags() -> [String] {
        return tagsArray.sorted()
    }
}

