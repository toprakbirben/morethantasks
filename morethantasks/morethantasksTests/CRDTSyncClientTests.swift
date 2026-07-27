//  CRDTSyncClientTests.swift
//  Covers CRDTSyncClient's wire encoding/decoding and HTTP-status → typed-error
//  mapping (Section 3's transport). Why it matters: a mismatch between this
//  client's JSON shape and notes-api's CRDTOp/CRDTOpsBatch models would fail
//  silently as a 422 in production but pass any test that only checks Swift
//  types — these tests assert on the actual request body sent.

import Testing
import Foundation
@testable import morethantasks

@Suite(.serialized)
struct CRDTSyncClientTests {

    private func client(status: Int, json: [String: Any] = [:]) -> CRDTSyncClient {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        MockURLProtocol.reset { _ in (status, data) }
        return CRDTSyncClient(session: .mock())
    }

    @Test func pushSendsOpTypeCharAndIdsInSnakeCase() async throws {
        var capturedBody: Data?
        MockURLProtocol.reset { request in
            capturedBody = request.httpBodyData()
            return (201, Data())
        }
        let sut = CRDTSyncClient(session: .mock())
        let site = UUID()
        let op = RGAOp(type: .insert, id: CharID(lamport: 1, siteId: site), parentId: nil, char: "x")

        try await sut.push(ops: [op], noteId: UUID(), materializedBody: "x", requesterId: 7)

        let bodyData = try #require(capturedBody)
        let jsonObject = try JSONSerialization.jsonObject(with: bodyData)
        let json = try #require(jsonObject as? [String: Any])
        #expect(json["requester_id"] as? Int == 7)
        #expect(json["materialized_body"] as? String == "x")
        let ops = try #require(json["ops"] as? [[String: Any]])
        #expect(ops.count == 1)
        #expect(ops[0]["op_type"] as? String == "insert")
        #expect(ops[0]["char"] as? String == "x")
        #expect(ops[0]["lamport"] as? Int == 1)
        #expect(ops[0]["site_id"] as? String == site.uuidString)
    }

    @Test func pushThrowsServerErrorOnNon2xx() async {
        let sut = client(status: 403)
        let op = RGAOp(type: .insert, id: CharID(lamport: 1, siteId: UUID()), parentId: nil, char: "x")
        await #expect(throws: CRDTSyncError.server(403)) {
            try await sut.push(ops: [op], noteId: UUID(), materializedBody: "x", requesterId: 1)
        }
    }

    @Test func pullDecodesOpsAndLatestSeq() async throws {
        let site = UUID()
        let sut = client(status: 200, json: [
            "ops": [[
                "op_type": "insert",
                "char": "y",
                "after_lamport": NSNull(),
                "after_site_id": NSNull(),
                "lamport": 3,
                "site_id": site.uuidString,
            ]],
            "latest_seq": 42,
        ])

        let (ops, latestSeq) = try await sut.pull(noteId: UUID(), since: 0, requesterId: 1)

        #expect(latestSeq == 42)
        #expect(ops == [RGAOp(type: .insert, id: CharID(lamport: 3, siteId: site), parentId: nil, char: "y")])
    }

    @Test func pullWithNoNewOpsReturnsEmptyAndSinceAsLatestSeq() async throws {
        let sut = client(status: 200, json: ["ops": [], "latest_seq": 5])
        let (ops, latestSeq) = try await sut.pull(noteId: UUID(), since: 5, requesterId: 1)
        #expect(ops.isEmpty)
        #expect(latestSeq == 5)
    }

    @Test func pullThrowsServerErrorOnUnauthorized() async {
        let sut = client(status: 403)
        await #expect(throws: CRDTSyncError.server(403)) {
            _ = try await sut.pull(noteId: UUID(), since: 0, requesterId: 1)
        }
    }
}

private extension URLRequest {
    /// httpBody is nil on requests captured via URLProtocol in some
    /// URLSession configurations; MockURLProtocol receives the original
    /// request object built by CRDTSyncClient, which does set httpBody directly.
    func httpBodyData() -> Data? { httpBody }
}
