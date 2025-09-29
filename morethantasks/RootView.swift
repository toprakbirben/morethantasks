//
//  RootView.swift
//  morethantasks
//
//  Created by Toprak Birben on 29/08/2025.
//

import SwiftUI

struct RootView: View {
    @Binding var selectedTab: UIComponents.Tab
    @Binding var notes: [Notes]
    
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            switch selectedTab {
            case .home:
                AnyView(LandingPage(selectedTab: $selectedTab))
            case .notes:
                AnyView(NoteView(selectedTab: $selectedTab))
            case .calendar:
                AnyView(CalendarPage(selectedTab: $selectedTab))
            @unknown default:
                AnyView(EmptyView())
            }

            UIComponents.TaskBar(selectedTab: $selectedTab)
        }
    }
}

// Preview
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView(selectedTab: .constant(.home),notes: .constant([]))
    }
}
