//  TagSharingService.swift
//  Client for tag-sharing endpoints (routers/tags.py): invite a collaborator
//  to a whole tag by name, list/respond to tag invites, and fetch a shared
//  tag's notes. Mirrors SharingService's per-note flow, but keyed by tag name
//  (owner-side) or tag_id (once a share exists) rather than a note id.
import Foundation

struct TagCollaborator: Identifiable, Decodable {
    let id: Int
    let email: String
    let status: String  // "pending" | "accepted"
}

struct PendingTagInvite: Identifiable, Decodable {
    let tagId: String
    let tagName: String
    let ownerEmail: String

    var id: String { tagId }

    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
        case tagName = "tag_name"
        case ownerEmail = "owner_email"
    }
}

struct SharedTag: Identifiable, Decodable {
    let id: String
    let name: String
    let ownerEmail: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerEmail = "owner_email"
    }
}

@MainActor
final class TagSharingService {
    static let shared = TagSharingService()

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    private var requesterId: Int { UserDefaults.standard.integer(forKey: "loggedInUserId") }

    func invite(email: String, toTag tagName: String) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/tags/invite") else {
            throw SharingError.network
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "requester_id": requesterId,
            "tag_name": tagName,
            "email": email,
        ])

        let (_, status) = try await perform(request)
        switch status {
        case 200, 201: return
        case 404: throw SharingError.noSuchAccount
        default:  throw SharingError.server(status)
        }
    }

    func fetchCollaborators(forTag tagName: String) async throws -> [TagCollaborator] {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/users/\(requesterId)/tags/\(tagName)/collaborators") else {
            throw SharingError.network
        }
        let (data, status) = try await perform(URLRequest(url: url))
        guard (200...299).contains(status) else { throw SharingError.server(status) }
        guard let decoded = try? JSONDecoder().decode([String: [TagCollaborator]].self, from: data),
              let collaborators = decoded["collaborators"] else {
            throw SharingError.decoding
        }
        return collaborators
    }

    /// Tags this user has been invited to but hasn't responded to yet.
    func fetchPendingTagInvites() async throws -> [PendingTagInvite] {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/users/\(requesterId)/tag-invites") else {
            throw SharingError.network
        }
        let (data, status) = try await perform(URLRequest(url: url))
        guard (200...299).contains(status) else { throw SharingError.server(status) }
        guard let decoded = try? JSONDecoder().decode([String: [PendingTagInvite]].self, from: data),
              let invites = decoded["invites"] else {
            throw SharingError.decoding
        }
        return invites
    }

    func respond(toTag tagId: String, accept: Bool) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/tags/\(tagId)/invites/respond") else {
            throw SharingError.network
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "requester_id": requesterId,
            "accept": accept,
        ])

        let (_, status) = try await perform(request)
        switch status {
        case 200, 201: return
        case 404: throw SharingError.noPendingInvite
        default:  throw SharingError.server(status)
        }
    }

    /// Tags this user has accepted a share for (owned by someone else).
    func fetchSharedTags() async throws -> [SharedTag] {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/tags/shared-with-me?user_id=\(requesterId)") else {
            throw SharingError.network
        }
        let (data, status) = try await perform(URLRequest(url: url))
        guard (200...299).contains(status) else { throw SharingError.server(status) }
        guard let decoded = try? JSONDecoder().decode([String: [SharedTag]].self, from: data),
              let tags = decoded["tags"] else {
            throw SharingError.decoding
        }
        return tags
    }

    /// The full tagged tree (root notes under `tagId` plus all their
    /// descendants) -- requires an accepted share or ownership.
    func fetchNotes(forTag tagId: String) async throws -> [Notes] {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/tags/\(tagId)/notes?requester_id=\(requesterId)") else {
            throw SharingError.network
        }
        let (data, status) = try await perform(URLRequest(url: url))
        guard (200...299).contains(status) else { throw SharingError.server(status) }
        guard let decoded = try? JSONDecoder().decode([String: [SharedNoteDTO]].self, from: data),
              let dtos = decoded["notes"] else {
            throw SharingError.decoding
        }
        return dtos.compactMap { $0.toNotes() }
    }

    func rename(tagName: String, to newName: String) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/users/\(requesterId)/tags/\(tagName)") else {
            throw SharingError.network
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "requester_id": requesterId,
            "name": newName,
        ])

        let (_, status) = try await perform(request)
        guard (200...299).contains(status) else { throw SharingError.server(status) }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SharingError.decoding }
            return (data, http.statusCode)
        } catch let error as SharingError {
            throw error
        } catch {
            throw SharingError.network
        }
    }
}

/// Decodes GET /tags/{id}/notes rows into the app's `Notes` model.
private struct SharedNoteDTO: Decodable {
    let id: String
    let title: String
    let body: String
    let parentId: String?
    let lastUpdated: Double?
    let userId: Int
    let color: String?
    let tag: String?
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, body, tag, deleted
        case parentId = "parent_id"
        case lastUpdated = "last_updated"
        case userId = "user_id"
        case color
    }

    func toNotes() -> Notes? {
        guard let uuid = UUID(uuidString: id), !deleted else { return nil }
        return Notes(
            id: uuid,
            title: title,
            body: body,
            parentId: parentId.flatMap { UUID(uuidString: $0) },
            children: [],
            lastUpdated: lastUpdated.map { Date(timeIntervalSince1970: $0) } ?? Date(),
            userID: userId,
            colorHex: color,
            tag: tag
        )
    }
}
