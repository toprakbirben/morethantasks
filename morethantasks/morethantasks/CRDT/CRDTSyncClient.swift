//  CRDTSyncClient.swift
//  HTTP transport for the body CRDT op log (Section 3 of the design spec):
//  POST /notes/{id}/crdt_ops pushes a locally-generated batch and updates the
//  server's `notes.body` cache from a materialized snapshot; GET pulls
//  everything newer than a cursor. The server never interprets ops — it only
//  stores/returns them by (note_id, lamport, site_id) identity.
import Foundation

enum CRDTSyncError: Error, Equatable {
    case badURL
    case encoding
    case decoding
    case server(Int)
}

/// Wire shape for one op — flat and snake_case to match notes-api's CRDTOp,
/// distinct from RGAOp's own Codable form (used only for local SQLite).
private struct CRDTOpWire: Codable {
    let opType: String
    let char: String?
    let afterLamport: UInt64?
    let afterSiteId: String?
    let lamport: UInt64
    let siteId: String

    enum CodingKeys: String, CodingKey {
        case opType = "op_type"
        case char
        case afterLamport = "after_lamport"
        case afterSiteId = "after_site_id"
        case lamport
        case siteId = "site_id"
    }

    init(op: RGAOp) {
        opType = op.type.rawValue
        char = op.char
        afterLamport = op.parentId?.lamport
        afterSiteId = op.parentId?.siteId.uuidString
        lamport = op.id.lamport
        siteId = op.id.siteId.uuidString
    }

    func toRGAOp() -> RGAOp? {
        guard let type = RGAOpType(rawValue: opType),
              let siteUUID = UUID(uuidString: siteId) else { return nil }
        var parentId: CharID? = nil
        if let afterLamport, let afterSiteId, let afterSiteUUID = UUID(uuidString: afterSiteId) {
            parentId = CharID(lamport: afterLamport, siteId: afterSiteUUID)
        }
        return RGAOp(type: type, id: CharID(lamport: lamport, siteId: siteUUID), parentId: parentId, char: char)
    }
}

private struct PushRequestBody: Encodable {
    let requesterId: Int
    let ops: [CRDTOpWire]
    let materializedBody: String

    enum CodingKeys: String, CodingKey {
        case requesterId = "requester_id"
        case ops
        case materializedBody = "materialized_body"
    }
}

private struct PullResponseBody: Decodable {
    let ops: [CRDTOpWire]
    let latestSeq: Int64

    enum CodingKeys: String, CodingKey {
        case ops
        case latestSeq = "latest_seq"
    }
}

final class CRDTSyncClient {
    static let shared = CRDTSyncClient()

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    /// Pushes `ops` for `noteId` and updates the server's body cache from
    /// `materializedBody`. Throws on any non-2xx response.
    func push(ops: [RGAOp], noteId: UUID, materializedBody: String, requesterId: Int) async throws {
        guard let url = URL(string: "\(ServerConfig.apiBaseURL)/notes/\(noteId.uuidString)/crdt_ops") else {
            throw CRDTSyncError.badURL
        }
        let body = PushRequestBody(requesterId: requesterId, ops: ops.map(CRDTOpWire.init), materializedBody: materializedBody)
        guard let data = try? JSONEncoder().encode(body) else { throw CRDTSyncError.encoding }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CRDTSyncError.server(code)
        }
    }

    /// Pulls ops newer than `since`. Returns the ops plus the new cursor value
    /// to persist (unchanged from `since` when there's nothing new).
    func pull(noteId: UUID, since: Int64, requesterId: Int) async throws -> (ops: [RGAOp], latestSeq: Int64) {
        guard var components = URLComponents(string: "\(ServerConfig.apiBaseURL)/notes/\(noteId.uuidString)/crdt_ops") else {
            throw CRDTSyncError.badURL
        }
        components.queryItems = [
            URLQueryItem(name: "requester_id", value: String(requesterId)),
            URLQueryItem(name: "since", value: String(since)),
        ]
        guard let url = components.url else { throw CRDTSyncError.badURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CRDTSyncError.server(code)
        }
        guard let decoded = try? JSONDecoder().decode(PullResponseBody.self, from: data) else {
            throw CRDTSyncError.decoding
        }
        return (decoded.ops.compactMap { $0.toRGAOp() }, decoded.latestSeq)
    }
}
