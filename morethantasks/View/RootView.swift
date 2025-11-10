//
//  RootView.swift
//  morethantasks
//
//  Created by Toprak Birben on 29/08/2025.
//

import SwiftUI

struct RootView: View {
    @Binding var selectedTab: UIComponents.Tab
    
    var body: some View {
        
        
        VStack(spacing: 0) {
            switch selectedTab {
            case .home:
                LandingPage(selectedTab: $selectedTab)
            case .notes:
                NoteView(selectedTab: $selectedTab)
            case .calendar:
                CalendarPage(selectedTab: $selectedTab)
            case .welcome:
                WelcomeView(selectedTab: $selectedTab)
            case .login:
                LoginScreen(selectedTab: $selectedTab)
            default:
                AnyView(EmptyView())
            }
            if selectedTab != .welcome && selectedTab != .login {
                UIComponents.TaskBar(selectedTab: $selectedTab)
            }
            
        }
    }
}

// Preview
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView(selectedTab: .constant(.welcome))
    }
}
