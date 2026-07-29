//  TagSharingServiceTests.swift
//  Covers TagSharingService's HTTP-status → typed-error mapping, mirroring
//  SharingServiceTests. Why it matters: sharing a tag grants edit access to
//  every note under it (see routers/tags.py's recursive tree query), so a
//  wrong status→error mapping here is as consequential as the per-note case.

import Testing
import Foundation
@testable import morethantasks

@Suite(.serialized)
@MainActor
struct TagSharingServiceTests {

    private func service(status: Int, json: [String: Any] = [:]) -> TagSharingService {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        MockURLProtocol.reset { _ in (status, data) }
        return TagSharingService(session: .mock())
    }

    @Test func inviteSuccessDoesNotThrow() async throws {
        let sharing = service(status: 201)
        try await sharing.invite(email: "a@b.com", toTag: "Work")
    }

    @Test func inviteUnknownEmailMapsToNoSuchAccount() async {
        let sharing = service(status: 404)
        await #expect(throws: SharingError.noSuchAccount) {
            try await sharing.invite(email: "nobody@b.com", toTag: "Work")
        }
    }

    @Test func inviteServerErrorMapsToServer() async {
        let sharing = service(status: 500)
        await #expect(throws: SharingError.server(500)) {
            try await sharing.invite(email: "a@b.com", toTag: "Work")
        }
    }

    @Test func fetchCollaboratorsDecodesTheList() async throws {
        let sharing = service(status: 200, json: [
            "collaborators": [["id": 2, "email": "b@c.com", "status": "accepted"]]
        ])
        let collaborators = try await sharing.fetchCollaborators(forTag: "Work")
        #expect(collaborators.map(\.email) == ["b@c.com"])
        #expect(collaborators.map(\.status) == ["accepted"])
    }

    @Test func fetchSharedTagsDecodesTheList() async throws {
        let sharing = service(status: 200, json: [
            "tags": [["id": "tag-1", "name": "Work", "owner_email": "owner@b.com"]]
        ])
        let tags = try await sharing.fetchSharedTags()
        #expect(tags.map(\.name) == ["Work"])
        #expect(tags.map(\.ownerEmail) == ["owner@b.com"])
    }

    @Test func fetchPendingTagInvitesDecodesTheList() async throws {
        let sharing = service(status: 200, json: [
            "invites": [["tag_id": "tag-1", "tag_name": "Work", "owner_email": "owner@b.com"]]
        ])
        let invites = try await sharing.fetchPendingTagInvites()
        #expect(invites.map(\.tagId) == ["tag-1"])
        #expect(invites.map(\.tagName) == ["Work"])
    }

    @Test func respondWithNoPendingInviteMapsToNoPendingInvite() async {
        let sharing = service(status: 404)
        await #expect(throws: SharingError.noPendingInvite) {
            try await sharing.respond(toTag: "tag-1", accept: true)
        }
    }

    @Test func fetchNotesDecodesIntoTheNotesModel() async throws {
        let noteId = UUID()
        let sharing = service(status: 200, json: [
            "notes": [[
                "id": noteId.uuidString, "title": "Trip", "body": "Plan", "parent_id": NSNull(),
                "last_updated": 1_700_000_000.0, "user_id": 3, "color": "#28A745",
                "tag": "Work", "deleted": false
            ]]
        ])
        let notes = try await sharing.fetchNotes(forTag: "tag-1")
        #expect(notes.map(\.id) == [noteId])
        #expect(notes.map(\.title) == ["Trip"])
    }

    @Test func renameSuccessDoesNotThrow() async throws {
        let sharing = service(status: 200)
        try await sharing.rename(tagName: "Work", to: "Job")
    }

    @Test func renameServerErrorMapsToServer() async {
        let sharing = service(status: 500)
        await #expect(throws: SharingError.server(500)) {
            try await sharing.rename(tagName: "Work", to: "Job")
        }
    }
}
