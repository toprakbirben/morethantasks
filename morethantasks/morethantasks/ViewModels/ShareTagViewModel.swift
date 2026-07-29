//
//  ShareTagViewModel.swift
//  morethantasks
//

import Foundation

@MainActor
final class ShareTagViewModel: ObservableObject {
    @Published private(set) var collaborators: [TagCollaborator] = []
    @Published var errorMessage: String?
    @Published private(set) var isInviting = false

    let tagName: String
    private let tagSharing: TagSharingService
    init(tagName: String, tagSharing: TagSharingService? = nil) {
        self.tagName = tagName
        self.tagSharing = tagSharing ?? .shared
    }

    func loadCollaborators() async {
        do {
            collaborators = try await tagSharing.fetchCollaborators(forTag: tagName)
        } catch {
            // Non-fatal: leave the existing list, the invite path surfaces errors.
        }
    }

    func invite(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        isInviting = true
        defer { isInviting = false }
        do {
            try await tagSharing.invite(email: trimmed, toTag: tagName)
            await loadCollaborators()
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription ?? "Something went wrong."
        }
    }
}
