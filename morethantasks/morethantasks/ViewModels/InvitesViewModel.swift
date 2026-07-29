//
//  InvitesViewModel.swift
//  morethantasks
//

import Foundation

@MainActor
final class InvitesViewModel: ObservableObject {
    @Published private(set) var invites: [PendingInvite] = []
    @Published private(set) var tagInvites: [PendingTagInvite] = []
    @Published var errorMessage: String?
    @Published private(set) var respondingTo: String?

    /// Badge/row count across both note- and tag-invites.
    var totalCount: Int { invites.count + tagInvites.count }

    private let sharing: SharingService
    private let tagSharing: TagSharingService
    init(sharing: SharingService? = nil, tagSharing: TagSharingService? = nil) {
        self.sharing = sharing ?? .shared
        self.tagSharing = tagSharing ?? .shared
    }

    func loadInvites() async {
        do {
            invites = try await sharing.fetchPendingInvites()
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription ?? "Something went wrong."
        }
        do {
            tagInvites = try await tagSharing.fetchPendingTagInvites()
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// On accept, also triggers a sync so the now-shared note reaches this
    /// device's local store without waiting for the next periodic pass.
    func respond(to invite: PendingInvite, accept: Bool) async {
        errorMessage = nil
        respondingTo = invite.noteId.uuidString
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

    /// On accept, also triggers a sync so the now-shared tag's notes reach
    /// this device's local store without waiting for the next periodic pass.
    func respond(to invite: PendingTagInvite, accept: Bool) async {
        errorMessage = nil
        respondingTo = invite.tagId
        defer { respondingTo = nil }
        do {
            try await tagSharing.respond(toTag: invite.tagId, accept: accept)
            tagInvites.removeAll { $0.tagId == invite.tagId }
            if accept {
                await DatabaseManager.shared.forceSyncNow()
            }
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription ?? "Something went wrong."
        }
    }
}
