//
//  AuthService.swift
//  morethantasks
//
//  Created by Toprak Birben on 08/11/2025.
//
//  User authentication and account management over the REST API. The local
//  notes store (DatabaseManager) is seeded/purged here on login/delete. This
//  type owns nothing UI-related — ViewModels call it and translate the typed
//  errors below into user-facing messages.
//

import Foundation

/// Typed auth failures so callers can react (and message users) precisely,
/// instead of the old `Bool`/optional-`Error` that callers silently ignored.
enum AuthError: LocalizedError, Equatable {
    case invalidCredentials
    case duplicateEmail
    case requestFailed
    case network
    case server(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Incorrect email or password."
        case .duplicateEmail:      return "An account with this email already exists."
        case .requestFailed:       return "Something went wrong. Please try again."
        case .network:             return "Network error. Check your connection and try again."
        case .server(let code):    return "Server error (\(code)). Please try again."
        case .decoding:            return "Unexpected response from the server."
        }
    }
}

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    private enum Keys {
        static let userId = "loggedInUserId"
        static let userEmail = "loggedInUserEmail"
    }

    var currentUserEmail: String? {
        UserDefaults.standard.string(forKey: Keys.userEmail)
    }

    // MARK: - Auth operations

    func register(email: String, password: String) async throws {
        let (_, status) = try await post("/users", body: ["email": email, "password": password])
        switch status {
        case 201: return
        case 409: throw AuthError.duplicateEmail
        default:  throw AuthError.server(status)
        }
    }

    func login(email: String, password: String) async throws {
        let (data, status) = try await post("/sessions", body: ["email": email, "password": password])
        switch status {
        case 200: break
        case 401: throw AuthError.invalidCredentials
        default:  throw AuthError.server(status)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user"] as? [String: Any],
              let userId = user["id"] as? Int,
              let serverEmail = user["email"] as? String else {
            throw AuthError.decoding
        }

        UserDefaults.standard.set(userId, forKey: Keys.userId)
        UserDefaults.standard.set(serverEmail, forKey: Keys.userEmail)

        // Refresh the local view for this user and seed SQLite from the server
        // so an existing user isn't shown an empty app before the first sync.
        DatabaseManager.shared.userDidLogin()
    }

    func resetPassword(email: String, password: String) async throws {
        let (data, status) = try await post("/users/password-reset",
                                            body: ["email": email, "password": password])
        guard status == 200 else { throw AuthError.server(status) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? Bool else {
            throw AuthError.decoding
        }
        guard success else { throw AuthError.requestFailed }
    }

    func deleteAccount() async throws {
        let userId = UserDefaults.standard.integer(forKey: Keys.userId)
        guard userId > 0,
              let url = URL(string: "\(ServerConfig.apiBaseURL)/users/\(userId)") else {
            throw AuthError.requestFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let status = try await send(request)
        guard (200...299).contains(status) else { throw AuthError.server(status) }

        DatabaseManager.shared.purgeLocalData(forUser: userId)
        logout()
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: Keys.userId)
        UserDefaults.standard.removeObject(forKey: Keys.userEmail)
    }

    // MARK: - HTTP helpers

    private func post(_ path: String, body: [String: Any]) async throws -> (Data, Int) {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)\(path)") else {
            throw AuthError.network
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await perform(request)
        return (data, response.statusCode)
    }

    private func send(_ request: URLRequest) async throws -> Int {
        let (_, response) = try await perform(request)
        return response.statusCode
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.decoding }
            return (data, http)
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.network
        }
    }
}
