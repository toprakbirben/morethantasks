//
//  Calendar.swift
//  morethantasks
//
//  Created by Toprak Birben on 06/05/2025.
//
import SwiftUI

struct Calendar: View {
    @Binding var selectedTab: UIComponents.Tab

    
    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    Text("Calendar")
                }
            }

        }
    }
}

struct Calendar_Previews: PreviewProvider {
    static var previews: some View {
        Calendar(selectedTab: .constant(.calendar))
    }
}
