//
//  SyncStatusView.swift
//  morethantasks
//
//  Created by Toprak Birben on 01/06/2026.
//

import SwiftUI

struct SyncStatusView: View {
    @StateObject private var vm = SyncStatusViewModel()

    var body: some View {
        HStack(spacing: 8) {
            // Connection status
            Circle()
                .fill(vm.isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            // Status text
            if vm.isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if vm.pendingSyncCount > 0 {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("\(vm.pendingSyncCount) pending")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("Synced")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Last sync time
            if let lastSync = vm.lastSyncText {
                Text(lastSync)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Manual sync button
            Button {
                Task { await vm.sync() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .disabled(!vm.canSync)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }
}

#Preview {
    SyncStatusView()
        .padding()
}
