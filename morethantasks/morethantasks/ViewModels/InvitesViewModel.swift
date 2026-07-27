//
//  InvitesViewModel.swift
//  morethantasks
//

import Foundation

@MainActor
final class InvitesViewModel: ObservableObject {
    @Published private(set) var invites: [PendingInvite] = []
    @Published var errorMessage: String?
    @Published private(set) var respondingTo: UUID?

    private let sharing: SharingService
    init(sharing: SharingService? = nil) {
        self.sharing = sharing ?? .shared
    }

    func loadInvites() async {
        do {
            invites = try await sharing.fetchPendingInvites()
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// On accept, also triggers a sync so the now-shared note reaches this
    /// device's local store without waiting for the next periodic pass.
    func respond(to invite: PendingInvite, accept: Bool) async {
        errorMessage = nil
        respondingTo = invite.noteId
        defer { respondingTo = nil }
        do {
            try await sharing.respond(toNote: invite.noteId, accept: accept)
            invites.removeAll { $0.noteId == invite.noteId }
            if accept {
                await DatabaseManager.shared.forceSyncNow()
            }
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription ?? "Something went wrong."
        }
    }
}
