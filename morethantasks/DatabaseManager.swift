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
    func insert(title: String, noteBody: String, completion: @escaping () -> Void)
    func update(noteId: String, title: String?, noteBody: String?, noteParent: String?, noteColor: String?, completion: @escaping () -> Void)
    func delete(noteId: UUID, completion: @escaping () -> Void)
}

class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    
    private let postgres = PostgresDatabase()
    private let sqlite = SQLiteDatabase()
    
    @Published private(set) var activeDatabase: DatabaseProvider
    @Published var isConnected: Bool = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitorQueue")
    
    private var notesDict: [UUID: Notes] = [:]


    
    init() {
        activeDatabase = sqlite
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isConnected = path.status == .satisfied
                self.activeDatabase = self.isConnected ? self.postgres : self.sqlite
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
    
    func fetchNotes() {
        let fetchedNotes = activeDatabase.fetchNotes()
            for note in fetchedNotes {
                notesDict[note.id] = note
            }
    }
    
    func insert(note: Notes) {
        activeDatabase.insert(title: note.title, noteBody: note.body) {
            self.notesDict[note.id] = note
            print("Insert success for note \(note.id)")
        }
    }
    
    func update(note: Notes) {
        activeDatabase.update(
            noteId: note.id.uuidString,
            title: note.title,
            noteBody: note.body,
            noteParent: note.parentId?.uuidString,
            noteColor: note.colorHex
        ) {
            self.notesDict[note.id] = note
            print("Update success for note \(note.id)")
        }
    }
    
    func delete(noteId: UUID) {
        activeDatabase.delete(noteId: noteId) {
            self.notesDict.removeValue(forKey: noteId)
            print("Delete success for note \(noteId)")
        }
    }
    
    func getNotes() -> [Notes] {
        return Array(notesDict.values)
    }
}

