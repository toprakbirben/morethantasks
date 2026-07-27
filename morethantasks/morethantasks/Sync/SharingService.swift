//  SharingService.swift
//  Client for Section 4's sharing endpoints: invite a collaborator by email,
//  list a note's collaborators, and let an invitee accept/decline. Flat,
//  all-editors — no roles. An invite grants no access until accepted.
import Foundation

struct Collaborator: Identifiable, Decodable {
    let id: Int
    let email: String
    let status: String  // "pending" | "accepted"
}

struct PendingInvite: Identifiable, Decodable {
    let noteId: UUID
    let noteTitle: String
    let ownerEmail: String

    var id: UUID { noteId }

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case noteTitle = "note_title"
        case ownerEmail = "owner_email"
    }
}

enum SharingError: LocalizedError, Equatable {
    case notOwner
    case noSuchAccount
    case noPendingInvite
    case requestFailed
    case network
    case server(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notOwner:        return "Only the note's owner can invite collaborators."
        case .noSuchAccount:   return "No account found for that email."
        case .noPendingInvite: return "This invite is no longer pending."
        case .requestFailed:   return "Something went wrong. Please try again."
        case .network:         return "Network error. Check your connection and try again."
        case .server(let c):   return "Server error (\(c)). Please try again."
        case .decoding:        return "Unexpected response from the server."
        }
    }
}

@MainActor
final class SharingService {
    static let shared = SharingService()

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    private var requesterId: Int { UserDefaults.standard.integer(forKey: "loggedInUserId") }

    func invite(email: String, toNote noteId: UUID) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/notes/\(noteId.uuidString)/invite") else {
            throw SharingError.network
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "requester_id": requesterId,
            "email": email,
        ])

        let (_, status) = try await perform(request)
        switch status {
        case 200, 201: return
        case 403: throw SharingError.notOwner
        case 404: throw SharingError.noSuchAccount
        default:  throw SharingError.server(status)
        }
    }

    func fetchCollaborators(forNote noteId: UUID) async throws -> [Collaborator] {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/notes/\(noteId.uuidString)/collaborators") else {
            throw SharingError.network
        }
        let (data, status) = try await perform(URLRequest(url: url))
        guard (200...299).contains(status) else { throw SharingError.server(status) }
        guard let decoded = try? JSONDecoder().decode([String: [Collaborator]].self, from: data),
              let collaborators = decoded["collaborators"] else {
            throw SharingError.decoding
        }
        return collaborators
    }

    /// Notes this user has been invited to but hasn't accepted or declined yet.
    func fetchPendingInvites() async throws -> [PendingInvite] {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/users/\(requesterId)/invites") else {
            throw SharingError.network
        }
        let (data, status) = try await perform(URLRequest(url: url))
        guard (200...299).contains(status) else { throw SharingError.server(status) }
        guard let decoded = try? JSONDecoder().decode([String: [PendingInvite]].self, from: data),
              let invites = decoded["invites"] else {
            throw SharingError.decoding
        }
        return invites
    }

    /// Accepts or declines a pending invite. Accepting grants access on the
    /// next sync pass (fetchNotesForSync's pull-scope now includes it);
    /// declining removes the collaborator row entirely.
    func respond(toNote noteId: UUID, accept: Bool) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/notes/\(noteId.uuidString)/invites/respond") else {
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
