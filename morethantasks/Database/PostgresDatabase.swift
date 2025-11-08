//
//  PostgresDatabase.swift
//  morethantasks
//
//  Created by Toprak Birben on 29/08/2025.
//

import Foundation
import PostgresClientKit
import Combine

class PostgresDatabase: DatabaseProvider {

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

    // MARK: - Fetch
    func fetchNotes() -> [Notes] {
        var notes: [Notes] = []
        do {
            let connection = try PostgresClientKit.Connection(configuration: configuration)
            defer { connection.close() }

            let text = "SELECT * FROM notes"
            let statement = try connection.prepareStatement(text: text)
            let cursor = try statement.execute()
            defer { cursor.close() }

            for row in cursor {
                let columns = try row.get().columns
                guard let idString = try? columns[0].string(),
                      let id = UUID(uuidString: idString) else { continue }

                let title = try columns[1].string()
                let body = try columns[2].string()
                let parentIdString = try? columns[3].string()
                let parentId = parentIdString.flatMap { UUID(uuidString: $0) }
                let lastUpdated = try columns[4].timestamp().date(in: .current)
                let createdByUserId = try columns[5].string()
                let color = try? columns[6].string()
                let tag = try? columns[7].string()

                notes.append(Notes(
                    id: id,
                    title: title,
                    body: body,
                    parentId: parentId,
                    children: [],
                    lastUpdated: lastUpdated,
                    createdByUserId: createdByUserId,
                    colorHex: color,
                    tag: tag
                ))
            }
        } catch {
            print("Postgres fetch error:", error)
        }
        return notes
    }
    
    func fetchTags() -> [String] {
        var tags: [String] = []
        do {
            let connection = try PostgresClientKit.Connection(configuration: configuration)
            defer { connection.close() }

            let text = "SELECT DISTINCT tag FROM notes;"
            let statement = try connection.prepareStatement(text: text)
            let cursor = try statement.execute()
            defer { cursor.close() }

            for row in cursor {
                let tag = try row.get().columns[0].string()
                tags.append(tag)
            }
        } catch {
            print("Postgres fetchTags error:", error)
        }
        return tags
    }
    
    // MARK: - Insert
    func insert(title: String, noteBody: String, tag: String?, completion: @escaping () -> Void) {
        guard let url = URL(string: "http://192.168.178.187:8000/add_note") else { return }
        let noteData: [String: Any] = [
            "title": title,
            "body": noteBody,
            "tag" : tag ?? "",
            "created_by_user_id": "toprak"
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: noteData) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                print("Postgres insert error:", error)
            } else {
                print("✅ Note added to Postgres")
                DispatchQueue.main.async { completion() }
            }
        }.resume()
    }

    // MARK: - Update
    func update(noteId: String, title: String?, noteBody: String?,noteParent: String?, noteColor: String?, tag: String?, completion: @escaping () -> Void) {

        guard let url = URL(string: "http://192.168.178.187:8000/edit_note") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["note_id": noteId]
        if let title = title {body["title"] = title}
        if let noteBody = noteBody {body["body"] = noteBody}
        if let noteParent = noteParent {body["parent_id"] = noteParent}
        if let noteColor = noteColor {body["color"] = noteColor}
        if let tag = tag {body["tag"] = tag}

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                print("Postgres update error:", error)
            } else {
                print("✅ Note updated in Postgres")
                DispatchQueue.main.async { completion() }
            }
        }.resume()
    }

    // MARK: - Delete
    func delete(noteId: UUID, completion: @escaping () -> Void) {
        guard let url = URL(string: "http://192.168.178.187:8000/remove_note") else { return }
        let noteData: [String: Any] = ["note_id": noteId.uuidString]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: noteData) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                print("Postgres delete error:", error)
            } else {
                print("✅ Note deleted from Postgres")
                DispatchQueue.main.async { completion() }
            }
        }.resume()
    }
}
