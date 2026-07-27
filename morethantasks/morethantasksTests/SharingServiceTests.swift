//  SharingServiceTests.swift
//  Covers SharingService's HTTP-status → typed-error mapping (Section 4).
//  Why it matters: 403 (not owner) and 404 (no such account) must surface as
//  distinct, actionable errors — collapsing them to a generic failure would
//  leave the user unable to tell "you can't do that" from "check the email".

import Testing
import Foundation
@testable import morethantasks

@Suite(.serialized)
@MainActor
struct SharingServiceTests {

    private func service(status: Int, json: [String: Any] = [:]) -> SharingService {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        MockURLProtocol.reset { _ in (status, data) }
        return SharingService(session: .mock())
    }

    @Test func inviteSuccessDoesNotThrow() async throws {
        let sharing = service(status: 201)
        try await sharing.invite(email: "a@b.com", toNote: UUID())
    }

    @Test func inviteForbiddenMapsToNotOwner() async {
        let sharing = service(status: 403)
        await #expect(throws: SharingError.notOwner) {
            try await sharing.invite(email: "a@b.com", toNote: UUID())
        }
    }

    @Test func inviteUnknownEmailMapsToNoSuchAccount() async {
        let sharing = service(status: 404)
        await #expect(throws: SharingError.noSuchAccount) {
            try await sharing.invite(email: "nobody@b.com", toNote: UUID())
        }
    }

    @Test func inviteServerErrorMapsToServer() async {
        let sharing = service(status: 500)
        await #expect(throws: SharingError.server(500)) {
            try await sharing.invite(email: "a@b.com", toNote: UUID())
        }
    }

    @Test func fetchCollaboratorsDecodesTheList() async throws {
        let sharing = service(status: 200, json: [
            "collaborators": [["id": 2, "email": "b@c.com", "status": "accepted"]]
        ])
        let collaborators = try await sharing.fetchCollaborators(forNote: UUID())
        #expect(collaborators.map(\.email) == ["b@c.com"])
        #expect(collaborators.map(\.status) == ["accepted"])
    }

    @Test func fetchCollaboratorsMalformedBodyMapsToDecoding() async {
        let sharing = service(status: 200, json: ["unexpected": true])
        await #expect(throws: SharingError.decoding) {
            _ = try await sharing.fetchCollaborators(forNote: UUID())
        }
    }

    // MARK: - Pending invites (accept/decline)
    //
    // Why it matters: an invite must not grant access until the invitee
    // responds — these map the endpoints that make that consent explicit.

    @Test func fetchPendingInvitesDecodesTheList() async throws {
        let noteId = UUID()
        let sharing = service(status: 200, json: [
            "invites": [["note_id": noteId.uuidString, "note_title": "Trip plan", "owner_email": "owner@b.com"]]
        ])
        let invites = try await sharing.fetchPendingInvites()
        #expect(invites.map(\.noteId) == [noteId])
        #expect(invites.map(\.noteTitle) == ["Trip plan"])
        #expect(invites.map(\.ownerEmail) == ["owner@b.com"])
    }

    @Test func respondAcceptSuccessDoesNotThrow() async throws {
        let sharing = service(status: 200)
        try await sharing.respond(toNote: UUID(), accept: true)
    }

    @Test func respondWithNoPendingInviteMapsToNoPendingInvite() async {
        let sharing = service(status: 404)
        await #expect(throws: SharingError.noPendingInvite) {
            try await sharing.respond(toNote: UUID(), accept: true)
        }
    }
}
