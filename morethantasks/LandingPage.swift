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
    @State private var searchText: String = ""
    
    @StateObject private var rm = ReminderManager.shared
    @StateObject private var db = DatabaseManager.shared

    
    var body: some View {
        NavigationStack {
            VStack {
                UIComponents.SearchBar(searchText: $searchText)
                ScrollView {
                    VStack(spacing: 16) {
                        if !searchText.isEmpty {
                            ForEach(Helper.shared.filteredNotes(searchText: searchText, notes: db.notesArray)) { note in
                                NavigationLink(
                                    destination: NoteDetailView(note: note, tagsArray: $db.tagsArray) { updatedTitle, updatedText, updatedTag in
                                        var updatedNote = note
                                        updatedNote.title = updatedTitle
                                        updatedNote.body = updatedText
                                        updatedNote.tag = updatedTag
                                        DatabaseManager.shared.update(note: updatedNote)
                                    }
                                ) {
                                    UIComponents.NoteCell(note: note)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                        }
                        TaskLookup(reminders: $rm.remindersArray)
                        FeaturedNotes(recentNotes: $db.notesArray)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .animation(.easeInOut(duration: 0.3), value: searchText)
                }
            }
        }
    }
}




struct TaskLookup: View {
    @Binding var reminders: [Reminder]

    var body: some View {
        GeometryReader  { geometry in
            List($reminders) { $task in
                HStack {
                    Image(systemName: task.isCompleted
                                      ? "largecircle.fill.circle"
                                      : "circle")
                        .imageScale(.small)
                        .foregroundStyle(.tint)
                        .onTapGesture {
                            task.isCompleted.toggle()
                        }
                    VStack(alignment: .leading)
                    {
                        Text(task.body)
                        Text(task.dueDate.formatted(.dateTime.year().month().day()))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(height: geometry.size.height + 10)
            .listStyle(.plain)
        }
        .frame(height:100)
    }
}


struct FeaturedNotes: View {
    @Binding var recentNotes: [Notes]
    var body: some View {
        GeometryReader { geometry in
            let rectHeight = geometry.size.height / 3
            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 50, maximum: .infinity)),
                GridItem(.flexible(minimum: 50, maximum: .infinity))
            ], spacing: 20) {
                ForEach(0..<6) { index in
                    Rectangle()
                        .fill(Color.blue)
                        .cornerRadius(10)
                        .frame(height: rectHeight)
                        .overlay(Text("\(index + 1)").foregroundColor(.white))
                        .padding(4)
                        
                }
            }
            .padding()
        }.frame(height: 380)
    }
}


struct LandingPage_Previews: PreviewProvider {
    static var previews: some View {
        LandingPage(selectedTab: .constant(.home))
    }
}
