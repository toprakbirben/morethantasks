//
//  ShareNoteViewModel.swift
//  morethantasks
//

import Foundation

@MainActor
final class ShareNoteViewModel: ObservableObject {
    @Published private(set) var collaborators: [Collaborator] = []
    @Published var errorMessage: String?
    @Published private(set) var isInviting = false

    private let noteId: UUID
    private let sharing: SharingService
    init(noteId: UUID, sharing: SharingService? = nil) {
        self.noteId = noteId
        self.sharing = sharing ?? .shared
    }

    func loadCollaborators() async {
        do {
            collaborators = try await sharing.fetchCollaborators(forNote: noteId)
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
            try await sharing.invite(email: trimmed, toNote: noteId)
            await loadCollaborators()
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription ?? "Something went wrong."
        }
    }
}
