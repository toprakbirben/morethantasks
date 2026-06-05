//
//  PostgresDatabase.swift
//  morethantasks
//
//  Created by Toprak Birben on 29/08/2025.
//
//  Remote sync target only. The app never reads this for UI — SQLite is the
//  source of truth. These methods are the push (insert/update/delete via the
//  HTTP API) and pull (fetchNotesForSync via a direct, BLOCKING PG read).
//  Callers must run fetchNotesForSync off the main thread.
//

import Foundation
import PostgresClientKit
import Combine

enum PostgresPushError: Error {
    case badURL
    case encoding
    case server(Int)
}

class PostgresDatabase {

    private var configuration: PostgresClientKit.ConnectionConfiguration

    init() {
        configuration = PostgresClientKit.ConnectionConfiguration()
        configuration.host = ServerConfig.host
        configuration.port = 5432
        configuration.database = "notes"
        configuration.user = "notes"
        configuration.credential = .scramSHA256(password: "notes")
        configuration.ssl = false
    }

    // MARK: - Pull (BLOCKING — call off the main thread)
    //
    // Returns the user's active notes plus the ids of notes the server has
    // tombstoned (deleted = true), so the engine can converge local state.
    // If the server schema lacks the `deleted` column yet, the query throws
    // and we return empty — pull safely no-ops until the server is updated.

    func fetchNotesForSync(forUser userId: Int) -> (active: [Notes], deletedIds: [UUID]) {
        var active: [Notes] = []
        var deletedIds: [UUID] = []
        do {
            let connection = try PostgresClientKit.Connection(configuration: configuration)
            defer { connection.close() }

            let text = "SELECT id, title, body, parent_id, last_updated, user_id, color, tag, deleted FROM notes;"
            let statement = try connection.prepareStatement(text: text)
            let cursor = try statement.execute()
            defer { cursor.close() }

            for row in cursor {
                let columns = try row.get().columns
                guard let idString = try? columns[0].string(),
                      let id = UUID(uuidString: idString),
                      (try? columns[5].int()) == userId else { continue }

                let isDeleted = (try? columns[8].bool()) ?? false
                if isDeleted {
                    deletedIds.append(id)
                    continue
                }

                let title = try columns[1].string()
                let body = try columns[2].string()
                let parentIdString = try? columns[3].string()
                let parentId = parentIdString.flatMap { UUID(uuidString: $0) }
                let lastUpdated = try columns[4].timestamp().date(in: .current)
                let createdByUserId = try columns[5].int()
                let color = try? columns[6].string()
                let tag = try? columns[7].string()

                active.append(Notes(
                    id: id,
                    title: title,
                    body: body,
                    parentId: parentId,
                    children: [],
                    lastUpdated: lastUpdated,
                    userID: createdByUserId,
                    colorHex: color,
                    tag: tag
                ))
            }
        } catch {
            print("Postgres fetchNotesForSync error:", error)
        }
        return (active, deletedIds)
    }

    // MARK: - Push: Insert
    //
    // Sends the client-generated note_id so SQLite and Postgres share one id.
    // The server must INSERT with this id (ON CONFLICT (id) DO NOTHING) for
    // retries to be idempotent. See SERVER_CHANGES_REQUIRED.md.

    func insert(_ note: Notes) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/notes") else {
            throw PostgresPushError.badURL
        }

        let noteData: [String: Any] = [
            "note_id": note.id.uuidString,
            "title": note.title,
            "body": note.body,
            "tag": note.tag ?? "",
            "color": note.colorHex ?? "",
            "parent_id": note.parentId?.uuidString ?? "",
            "last_updated": note.lastUpdated.timeIntervalSince1970,
            "user_id": note.userID
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: noteData) else {
            throw PostgresPushError.encoding
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        try await send(request)
    }

    // MARK: - Push: Update

    func update(noteId: String, title: String?, noteBody: String?, noteParent: String?, noteColor: String?, tag: String?) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/notes/\(noteId)") else {
            throw PostgresPushError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [:]
        if let title = title { body["title"] = title }
        if let noteBody = noteBody { body["body"] = noteBody }
        if let noteParent = noteParent { body["parent_id"] = noteParent }
        if let noteColor = noteColor { body["color"] = noteColor }
        if let tag = tag { body["tag"] = tag }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw PostgresPushError.encoding
        }
        request.httpBody = jsonData

        try await send(request)
    }

    // MARK: - Push: Delete (server performs a soft delete / tombstone)

    func delete(noteId: UUID) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/notes/\(noteId.uuidString)") else {
            throw PostgresPushError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        try await send(request)
    }

    /// Performs the request and throws unless the server returns 2xx (or no
    /// HTTP status, which we treat as success to match prior behavior).
    private func send(_ request: URLRequest) async throws {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw PostgresPushError.server(http.statusCode)
        }
    }
}
