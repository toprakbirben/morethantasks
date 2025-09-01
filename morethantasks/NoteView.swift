//
//  NoteView.swift
//  morethantasks
//
//  Created by Toprak Birben on 25/08/2025.
//
import SwiftUI

struct NoteView: View {
    @Binding var selectedTab: UIComponents.Tab
    @State private var tree: [Notes] = []

    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    UIComponents.SearchBar()
                    RecentNoteView(notes: tree)
                    NoteListView(notes: tree)
                }
            }
        }
        .onAppear {
            let notes = PostgresDatabase.shared.fetchNotes()
            tree = PostgresDatabase.buildNoteTree(from: notes)
        }
    }
}


struct NoteList: View {
    let note: Notes
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // --- Note Card ---
            HStack {
                Text(note.title)
                    .font(.headline)
                Spacer()
                if !note.children.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

            // --- Children ---
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(note.children, id: \.id) { child in
                        NoteList(note: child) // recursive
                            .padding(.leading, 20)
                    }
                }
            }
        }
    }
}

struct RecentNoteView: View {
    let notes: [Notes]
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "clock").imageScale(.small)
                Text("Recenten").font(.headline)
            }.padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false){
                HStack(spacing: 20) {
                    ForEach(notes, id: \.id) { note in
                        Button(action: {
                            print("Note tapped!")
                        }) {
                            Text("📌 Note Title")
                                .padding()
                                .background(Color.green.opacity(0.8))
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        
    }
}

struct NoteListView: View {
    let notes: [Notes]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(notes, id: \.id) { note in
                Button(action: {
                    print("Note tapped!")
                }) {
                    Text("\(note.title)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal)
    }
}


struct NoteView_Previews: PreviewProvider {
    static var previews: some View {
        NoteView(selectedTab: .constant(.notes))
    }
}
