//  ShareNoteSheet.swift
//  Minimal Section 4 sharing UI: enter an email to invite, see the current
//  collaborator list. No presence/cursors/avatars — out of scope for v1.
import SwiftUI

struct ShareNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: ShareNoteViewModel
    @State private var email: String = ""

    init(noteId: UUID) {
        _vm = StateObject(wrappedValue: ShareNoteViewModel(noteId: noteId))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite by email") {
                    HStack {
                        TextField("name@example.com", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .disableAutocorrection(true)
                        Button("Invite") {
                            Task {
                                await vm.invite(email: email)
                                email = ""
                            }
                        }
                        .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || vm.isInviting)
                    }
                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage).foregroundColor(.red).font(.footnote)
                    }
                }

                Section("Collaborators") {
                    if vm.collaborators.isEmpty {
                        Text("No collaborators yet.").foregroundColor(.secondary)
                    } else {
                        ForEach(vm.collaborators) { collaborator in
                            HStack {
                                Text(collaborator.email)
                                Spacer()
                                if collaborator.status == "pending" {
                                    Text("Pending").foregroundColor(.secondary).font(.footnote)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Share Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await vm.loadCollaborators() }
        }
    }
}
