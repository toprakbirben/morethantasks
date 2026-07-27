//  ShareNoteViewModelTests.swift
//  Covers ShareNoteViewModel's validation gating and error surfacing.
//  Why it matters: an empty/whitespace-only email must never fire a network
//  request (wastes a round trip, invites a confusing server error), and a
//  failed invite must not silently clear the form.

import Testing
import Foundation
@testable import morethantasks

@Suite(.serialized)
@MainActor
struct ShareNoteViewModelTests {

    private func viewModel(status: Int, json: [String: Any] = [:]) -> ShareNoteViewModel {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        MockURLProtocol.reset { _ in (status, data) }
        return ShareNoteViewModel(noteId: UUID(), sharing: SharingService(session: .mock()))
    }

    @Test func inviteWithEmptyEmailNeverHitsNetwork() async {
        let vm = viewModel(status: 200)
        await vm.invite(email: "   ")
        #expect(MockURLProtocol.didReceiveRequest == false)
    }

    @Test func inviteSuccessClearsErrorAndRefreshesCollaborators() async {
        MockURLProtocol.reset { request in
            // invite POST vs collaborators GET share one responder; both succeed.
            if request.httpMethod == "POST" {
                return (201, Data())
            }
            let body = try! JSONSerialization.data(withJSONObject: ["collaborators": [["id": 1, "email": "a@b.com", "status": "pending"]]])
            return (200, body)
        }
        let vm = ShareNoteViewModel(noteId: UUID(), sharing: SharingService(session: .mock()))

        await vm.invite(email: "a@b.com")

        #expect(vm.errorMessage == nil)
        #expect(vm.collaborators.map(\.email) == ["a@b.com"])
    }

    @Test func inviteFailureSurfacesErrorMessage() async {
        let vm = viewModel(status: 403)
        await vm.invite(email: "a@b.com")
        #expect(vm.errorMessage == SharingError.notOwner.errorDescription)
    }

    @Test func loadCollaboratorsPopulatesTheList() async {
        let vm = viewModel(status: 200, json: ["collaborators": [["id": 3, "email": "c@d.com", "status": "accepted"]]])
        await vm.loadCollaborators()
        #expect(vm.collaborators.map(\.email) == ["c@d.com"])
    }
}
