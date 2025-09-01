//
//  LandingPage.swift
//  morethantasks
//
//  Created by Toprak Birben on 29/04/2025.
//

import SwiftUI


enum Tab {
    case home, notes, calendar
}

struct LandingPage: View {
    @Binding var selectedTab: UIComponents.Tab
    @State private var tree: [Notes] = []
    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    UIComponents.SearchBar()
                    TaskLookup()
                    FeaturedNotes(recentNotes: tree)
                }
            }
        }.onAppear {
            let notes = PostgresDatabase.shared.fetchNotes()
            tree = PostgresDatabase.buildNoteTree(from: notes)
        }
    }
}
    


struct TaskLookup: View {
    var body: some View {
        ScrollView
        {
            List(0 ..< 3) { item in
                HStack {
                    Image(systemName: "globe")
                        .imageScale(.small)
                        .foregroundStyle(.tint)
                    Text("Some task xyz")
                }
            }
            .listStyle(.plain)
            .frame(width: 360, height: 100)
        }
    }
}

struct FeaturedNotes: View {
    let recentNotes: [Notes]
    var body: some View {
        VStack() {
            RoundedRectangle(cornerRadius: 20)
                .frame(height: 75)
                .foregroundColor(Color(.green))
            HStack {
                RoundedRectangle(cornerRadius: 20)
                    .frame(height: 129)
                    .foregroundColor(Color(.purple))
                
                RoundedRectangle(cornerRadius: 20)
                    .frame(height: 129)
                    .foregroundColor(Color(.purple))
                
            }
            HStack {
                RoundedRectangle(cornerRadius: 20)
                    .frame(width: 111, height: 39)
                    .foregroundColor(Color(.yellow))
                
                RoundedRectangle(cornerRadius: 20)
                    .frame(height: 39
                    )
                    .foregroundColor(Color(.yellow))
            }
            HStack {
                RoundedRectangle(cornerRadius: 20)
                    .frame(width: 213, height: 113)
                    .foregroundColor(Color(.blue))
                RoundedRectangle(cornerRadius: 20)
                    .frame(height: 113)
                    .foregroundColor(Color(.blue))
            }
        }
        .padding(.horizontal, 16.0)
    }
}


struct LandingPage_Previews: PreviewProvider {
    static var previews: some View {
        LandingPage(selectedTab: .constant(.home))
    }
}
