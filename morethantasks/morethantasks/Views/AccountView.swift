//
//  AccountView.swift
//  morethantasks
//
//  Created by Toprak Birben on 12/11/2025.
//

import SwiftUI
import Foundation


struct AccountView : View {
    @StateObject private var vm = AccountViewModel()
    @StateObject private var invitesVM = InvitesViewModel()
    @Binding var selectedTab: UIComponents.Tab
    @State private var showInvites = false
    @State private var showDeleteConfirmation = false

    private var pendingInvitesCount: Int {
        invitesVM.invites.count + invitesVM.tagInvites.count
    }

    var body: some View {

        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 88, height: 88)
                        .foregroundColor(Color("primary-blue"))
                    Text(vm.userEmail)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 32)

                VStack(spacing: 12) {
                    Button {
                        showInvites = true
                    } label: {
                        settingsRow(title: "Invites", badgeCount: pendingInvitesCount)
                    }
                    .sheet(isPresented: $showInvites) {
                        InvitesView()
                    }
                    .task { await invitesVM.loadInvites() }

                    NavigationLink {
                        SharedTagsView()
                    } label: {
                        settingsRow(title: "Shared Tags", badgeCount: 0)
                    }
                }
                .padding(.horizontal, 32)

                VStack(spacing: 16) {
                    Button {
                        vm.logout()
                    } label: {
                        Text("Log Out")
                            .foregroundColor(Color("primary-blue"))
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Delete Account")
                    }
                    .confirmationDialog(
                        "Delete Account",
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Account", role: .destructive) {
                            Task { await vm.deleteAccount() }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This can't be undone.")
                    }
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .onChange(of: vm.didSignOut) { _, didSignOut in
                if didSignOut { selectedTab = .welcome }
            }
        }
    }

    private func settingsRow(title: String, badgeCount: Int) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Circle().fill(Color.red))
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color("primary-blue").opacity(0.4), lineWidth: 1)
        )
    }
}

struct AccountSetting: PreviewProvider {
    static var previews: some View {
        RootView(selectedTab: .constant(.login))
    }
}
