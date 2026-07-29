//  InvitesViewModelTests.swift
//  Covers InvitesViewModel's load/respond flow. Why it matters: declining (or
//  a failed accept) must not silently leave a stale invite in the list, and a
//  successful respond must remove the invite immediately rather than waiting
//  for a reload — the user just acted on it and expects it gone.

import Testing
import Foundation
@testable import morethantasks

@Suite(.serialized)
@MainActor
struct InvitesViewModelTests {

    private func pendingInviteJSON(noteId: UUID) -> [String: Any] {
        ["invites": [["note_id": noteId.uuidString, "note_title": "Shared note", "owner_email": "owner@b.com"]]]
    }

    private func pendingTagInviteJSON(tagId: String) -> [String: Any] {
        ["invites": [["tag_id": tagId, "tag_name": "Work", "owner_email": "owner@b.com"]]]
    }

    private func emptyInvitesJSON() -> [String: Any] { ["invites": [String]()] }

    /// Routes note- and tag-invite requests to separate mocked responses so
    /// loadInvites()'s two calls don't stomp on each other's decoding.
    private func respondByPath(notes: (Int, Data)? = nil, tags: (Int, Data)? = nil) {
        MockURLProtocol.reset { request in
            if request.url?.path.contains("tag-invites") == true || request.url?.path.hasPrefix("/tags/") == true {
                return tags ?? (200, try! JSONSerialization.data(withJSONObject: self.emptyInvitesJSON()))
            }
            return notes ?? (200, try! JSONSerialization.data(withJSONObject: self.emptyInvitesJSON()))
        }
    }

    private func makeVM() -> InvitesViewModel {
        InvitesViewModel(sharing: SharingService(session: .mock()), tagSharing: TagSharingService(session: .mock()))
    }

    @Test func loadInvitesPopulatesTheList() async {
        let noteId = UUID()
        let data = try! JSONSerialization.data(withJSONObject: pendingInviteJSON(noteId: noteId))
        respondByPath(notes: (200, data))
        let vm = makeVM()

        await vm.loadInvites()

        #expect(vm.invites.map(\.noteId) == [noteId])
    }

    @Test func loadInvitesPopulatesTagInvitesToo() async {
        let tagId = "tag-123"
        let data = try! JSONSerialization.data(withJSONObject: pendingTagInviteJSON(tagId: tagId))
        respondByPath(tags: (200, data))
        let vm = makeVM()

        await vm.loadInvites()

        #expect(vm.tagInvites.map(\.tagId) == [tagId])
        #expect(vm.totalCount == 1)
    }

    @Test func decliningRemovesTheInviteFromTheList() async {
        let noteId = UUID()
        let listData = try! JSONSerialization.data(withJSONObject: pendingInviteJSON(noteId: noteId))
        respondByPath(notes: (200, listData))
        let vm = makeVM()
        await vm.loadInvites()
        let invite = try! #require(vm.invites.first)

        await vm.respond(to: invite, accept: false)

        #expect(vm.invites.isEmpty)
    }

    @Test func decliningATagInviteRemovesItFromTheList() async {
        let tagId = "tag-456"
        let listData = try! JSONSerialization.data(withJSONObject: pendingTagInviteJSON(tagId: tagId))
        respondByPath(tags: (200, listData))
        let vm = makeVM()
        await vm.loadInvites()
        let invite = try! #require(vm.tagInvites.first)

        await vm.respond(to: invite, accept: false)

        #expect(vm.tagInvites.isEmpty)
    }

    @Test func failedRespondLeavesTheInviteInPlaceAndSurfacesAnError() async {
        let noteId = UUID()
        let listData = try! JSONSerialization.data(withJSONObject: pendingInviteJSON(noteId: noteId))
        respondByPath(notes: (200, listData))
        let vm = makeVM()
        await vm.loadInvites()
        let invite = try! #require(vm.invites.first)

        MockURLProtocol.reset { _ in (404, Data()) }
        await vm.respond(to: invite, accept: true)

        #expect(vm.invites.map(\.noteId) == [noteId])
        #expect(vm.errorMessage == SharingError.noPendingInvite.errorDescription)
    }
}
