//  ShareTagSheet.swift
//  Share a whole tag by email: invitees get full CRDT edit access to every
//  note under it (see routers/tags.py's recursive tree + crdt.py's
//  _is_authorized), not just the notes tagged today. Mirrors ShareNoteSheet.
import SwiftUI

struct ShareTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: ShareTagViewModel
    @State private var email: String = ""

    init(tagName: String) {
        _vm = StateObject(wrappedValue: ShareTagViewModel(tagName: tagName))
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
            .navigationTitle("Share \"\(vm.tagName)\"")
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
