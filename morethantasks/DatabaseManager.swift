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
                        self.notesArray.append(note)
                        print(self.notesArray)
                        print(note)
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
                    self.notesArray[index] = note
                    print("Update success for note inside of the closure \(note.id)")
                }
            }
        }
    }
    
    func delete(noteId: UUID) {
        activeDatabase.delete(noteId: noteId) {
            Task { @MainActor in
                self.notesArray.removeAll { $0.id == noteId }
                print("Delete success for note \(noteId)")
            }
        }
    }
    
    func getTags() -> [String] {
        return tagsArray.sorted()
    }
}

