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
    @State private var notes: [Notes] = []

    var body: some View {
        ZStack {
            VStack {
                ScrollView {
                    VStack {
                        UIComponents.SearchBar()
                        RecentNoteView(notes: tree)
                    }
                }.fixedSize(horizontal: false, vertical: true)
                NoteListView(notes: $tree, onRefresh: refreshNotes)
                HStack {
                    Spacer()
                    NoteAdd() {
                        refreshNotes()
                    }.background(.regularMaterial)
                }.padding()
            }
            
        }
        .onAppear {
            refreshNotes()
        }
    }
    
    private func refreshNotes() {
        notes = PostgresDatabase.shared.fetchNotes()
        tree = PostgresDatabase.buildNoteTree(from: notes)
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
                LazyHStack(spacing: 20) {
                    ForEach(notes, id: \.id) { note in
                        Button(action: {
                            print("Note tapped!")
                        }) {
                            Text("\(note.title)")
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
    @Binding var notes: [Notes]
    var onRefresh: (() -> Void)?

    var body: some View {
            List {
                ForEach(notes) { note in
                    NoteCell(title: note.title)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteNote(noteId: note.id.uuidString) {
                                    onRefresh?()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(PlainListStyle())
        }
}

struct NoteCell : View {
    let title: String
    var body: some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.green.opacity(0.8))
            .cornerRadius(10)
        
    }
}


func deleteNote(noteId: String, completion: @escaping () -> Void) {
    guard let url = URL(string: "http://192.168.178.187:8000/remove_note") else { return }
    
    let noteData: [String: Any] = ["note_id": noteId]
    
    guard let jsonData = try? JSONSerialization.data(withJSONObject: noteData) else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST" // your backend uses POST
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("Error deleting note:", error)
            return
        }
        
        if let data = data {
            if let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("Delete response:", responseJSON)
            }
        }
        
        DispatchQueue.main.async {
            completion()
        }
    }.resume()
}

func addNote(title: String, noteBody: String, completion: @escaping () -> Void) {
    guard let url = URL(string: "http://192.168.178.187:8000/add_note") else { return }
    
    let noteData: [String: Any] = [
        "title": title,
        "body": noteBody,
        "created_by_user_id": "toprak"
    ]
    
    guard let jsonData = try? JSONSerialization.data(withJSONObject: noteData) else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("Error adding note:", error)
        } else {
            print("Note added successfully")
            DispatchQueue.main.async {
                completion()
            }
        }
    }.resume()
}

struct NoteAdd: View {
    @State private var showNoteCreation = false
    var onNoteAdded: (() -> Void)?

    var body: some View {
        VStack {
            Button {
                showNoteCreation = true
            } label: {
                Image(systemName: "plus.app.fill")
                    .font(.system(size: 40))
            }
            .fullScreenCover(isPresented: $showNoteCreation) {
                NoteCreationView { title, body in
                    addNote(title: title, noteBody: body) {
                        onNoteAdded?()
                    }
                }
                    
            }
        }
    }
}

struct NoteCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    var onSave: (String, String) -> Void
    
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    if text.isEmpty { dismiss(); return }
                    let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                    let title = lines.first.map(String.init) ?? ""
                    let body = lines.count > 1 ? String(lines[1]) : ""
                    
                    onSave(title, body)  // save both
                    dismiss()
                }) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline)
                }
                Spacer()
                
            }
            .padding()

            TextEditor(text: $text)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .bottom)
        }
    }
}


struct NoteView_Previews: PreviewProvider {
    static var previews: some View {
        NoteView(selectedTab: .constant(.notes))
    }
}
