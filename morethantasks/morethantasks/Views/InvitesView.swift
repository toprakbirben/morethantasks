//  InvitesView.swift
//  Section 4 accept/decline UI: notes other users have shared with you that
//  you haven't responded to yet. Accepting is what actually grants access —
//  the note doesn't reach this device until then.
import SwiftUI

struct InvitesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = InvitesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.invites.isEmpty {
                    ContentUnavailableView("No Invites", systemImage: "envelope.open",
                                            description: Text("Notes shared with you will show up here."))
                } else {
                    List {
                        if let errorMessage = vm.errorMessage {
                            Text(errorMessage).foregroundColor(.red).font(.footnote)
                        }
                        ForEach(vm.invites) { invite in
                            row(for: invite)
                        }
                    }
                }
            }
            .navigationTitle("Invites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await vm.loadInvites() }
        }
    }

    private func row(for invite: PendingInvite) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(invite.noteTitle.isEmpty ? "Untitled" : invite.noteTitle)
                .font(.headline)
            Text("Shared by \(invite.ownerEmail)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                Button("Accept") {
                    Task { await vm.respond(to: invite, accept: true) }
                }
                .buttonStyle(.borderedProminent)

                Button("Decline", role: .destructive) {
                    Task { await vm.respond(to: invite, accept: false) }
                }
                .buttonStyle(.bordered)
            }
            .disabled(vm.respondingTo == invite.noteId)
        }
        .padding(.vertical, 4)
    }
}
