//
//  PostgresDatabase.swift
//  morethantasks
//
//  Created by Toprak Birben on 29/08/2025.
//

import Foundation
import PostgresClientKit

class PostgresDatabase {
    
    static let shared = PostgresDatabase()
    private var configuration: PostgresClientKit.ConnectionConfiguration
    
    init() {
        configuration = PostgresClientKit.ConnectionConfiguration()
        configuration.host = "192.168.178.187"
        configuration.port = 5432
        configuration.database = "notes"
        configuration.user = "notes"
        configuration.credential = .scramSHA256(password: "notes")
        configuration.ssl = false

    }
    
    // Fetch all notes
    func fetchNotes() -> [Notes] {
        var notes: [Notes] = []
        do {
            let connection = try PostgresClientKit.Connection(configuration: configuration)
            defer { connection.close() }
            
            let text = "SELECT id, title, body, parent_id, last_updated, created_by_user_id FROM notes"
            let statement = try connection.prepareStatement(text: text)
            let cursor = try statement.execute()
            defer{ cursor.close() }
            
            for row in cursor {
                let columns = try row.get().columns
        
                guard let idString = try? columns[0].string(),
                          let id = UUID(uuidString: idString) else {
                        continue
                    }
                let title: String = try columns[1].string()
                let body: String = try columns[2].string()
                let parentId: UUID?
                if let parentString = try? columns[3].string(), !parentString.isEmpty {
                    parentId = UUID(uuidString: parentString)
                } else {
                    parentId = nil
                }
                let children : [Notes] = []
                let lastUpdated = try columns[4].timestamp().date(in: .current)
                let createdByUserId = try columns[5].string()
                
                let note = Notes(
                        id: id,
                        title: title,
                        body: body,
                        parentId: parentId,
                        children: children,
                        lastUpdated: lastUpdated,
                        createdByUserId: createdByUserId
                    )
                notes.append(note)
            }
            if notes.isEmpty {
                print("✅ Successfully fetched notes, but no notes found.")
            } else {
                print("✅ Successfully fetched \(notes.count) notes.")
                let firstNote = notes[0]
                print("First note: \(firstNote.title) (ID: \(firstNote.id))")
                print("name of first note: \(firstNote.title)")
                
                if !firstNote.children.isEmpty {
                    print(" ↳ This note has \(firstNote.children.count) child notes.")
                    for child in firstNote.children {
                        print("    • \(child.title) (ID: \(child.id))")
                    }
                } else {
                    print(" ↳ This note has no child notes.")
                }
            }
        } catch {
            print("Postgres error: \(error)")
        }
        
        return notes
    }
    
    static func buildNoteTree(from notes: [Notes]) -> [Notes] {
        var lookup: [UUID: Notes] = [:]
        var roots: [Notes] = []
        
        for note in notes {
            lookup[note.id] = note
        }
        
        for note in notes {
            if let parentId = note.parentId {
                lookup[parentId]?.children.append(note)
            } else {
                roots.append(note)
            }
        }
        
        return roots
    }
    
    static func sortRecentNotes( notes: [Notes]) -> [Notes] {
        return notes.sorted { lhs, rhs in
                lhs.lastUpdated > rhs.lastUpdated
        }
    }
}
