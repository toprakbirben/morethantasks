//
//  SyncStatusView.swift
//  morethantasks
//
//  Created by Toprak Birben on 01/06/2026.
//

import SwiftUI

struct SyncStatusView: View {
    @StateObject private var dbManager = DatabaseManager.shared

    var body: some View {
        HStack(spacing: 8) {
            // Connection status
            Circle()
                .fill(dbManager.isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            // Status text
            if dbManager.isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if dbManager.pendingSyncCount > 0 {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("\(dbManager.pendingSyncCount) pending")
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
            if let lastSync = dbManager.lastSyncDate {
                Text(timeAgo(from: lastSync))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Manual sync button
            Button {
                Task {
                    await dbManager.forceSyncNow()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .disabled(dbManager.isSyncing || !dbManager.isConnected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }
    
    private func timeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }
    }
}

#Preview {
    SyncStatusView()
        .padding()
}
