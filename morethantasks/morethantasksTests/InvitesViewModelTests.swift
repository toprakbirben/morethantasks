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

    @Test func loadInvitesPopulatesTheList() async {
        let noteId = UUID()
        let data = try! JSONSerialization.data(withJSONObject: pendingInviteJSON(noteId: noteId))
        MockURLProtocol.reset { _ in (200, data) }
        let vm = InvitesViewModel(sharing: SharingService(session: .mock()))

        await vm.loadInvites()

        #expect(vm.invites.map(\.noteId) == [noteId])
    }

    @Test func decliningRemovesTheInviteFromTheList() async {
        let noteId = UUID()
        let listData = try! JSONSerialization.data(withJSONObject: pendingInviteJSON(noteId: noteId))
        MockURLProtocol.reset { _ in (200, listData) }
        let vm = InvitesViewModel(sharing: SharingService(session: .mock()))
        await vm.loadInvites()
        let invite = try! #require(vm.invites.first)

        await vm.respond(to: invite, accept: false)

        #expect(vm.invites.isEmpty)
    }

    @Test func failedRespondLeavesTheInviteInPlaceAndSurfacesAnError() async {
        let noteId = UUID()
        let listData = try! JSONSerialization.data(withJSONObject: pendingInviteJSON(noteId: noteId))
        MockURLProtocol.reset { _ in (200, listData) }
        let vm = InvitesViewModel(sharing: SharingService(session: .mock()))
        await vm.loadInvites()
        let invite = try! #require(vm.invites.first)

        MockURLProtocol.reset { _ in (404, Data()) }
        await vm.respond(to: invite, accept: true)

        #expect(vm.invites.map(\.noteId) == [noteId])
        #expect(vm.errorMessage == SharingError.noPendingInvite.errorDescription)
    }
}
