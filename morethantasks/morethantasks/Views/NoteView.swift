//
//  NoteView.swift
//  morethantasks
//
//  Created by Toprak Birben on 25/08/2025.
//

import SwiftUI
import Combine

struct NoteView: View {
    @Binding var selectedTab: UIComponents.Tab
    @State private var searchText: String = ""

    @StateObject private var vm = NotesViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                GeometryReader { geometry in
                    VStack {
                        UIComponents.SearchBar(searchText: $searchText, selectedTab: $selectedTab)

                        ScrollView(.horizontal, showsIndicators: false) {
                            RecentNoteView()
                        }.fixedSize(horizontal: false, vertical: true)

                        NoteListView()
                            .padding(.vertical)
                    }

                    NoteAdd()
                        .frame(width: 80, height: 80).position(x: geometry.size.width - 60, y: geometry.size.height - 128)
                }
            }
        }
        .environmentObject(vm)
    }
}

// MARK: - Recent Notes Horizontal View
struct RecentNoteView: View {
    @EnvironmentObject var vm: NotesViewModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "clock").imageScale(.small)
                Text("Recenten")
                    .font(.system(size: 16, weight: .light))
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(vm.notes, id: \.id) { note in
                        NavigationLink(
                            destination: NoteDetailView(note: note, tagsArray: .constant(vm.tags)) { updatedTitle, updatedText, updatedTag in
                                var updatedNote = note
                                updatedNote.title = updatedTitle
                                updatedNote.body = updatedText
                                updatedNote.tag = updatedTag
                                vm.update(updatedNote)
                            }
                        ) {
                            UIComponents.RecentNotes(
                                note: note,
                                widthOfNote: 100,
                                heightOfNote: 100
                            )
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

// MARK: - Note List View
struct NoteListView: View {
    @EnvironmentObject var vm: NotesViewModel

    @State private var selectedNote: Notes? = nil
    @State private var expanded: Set<UUID> = []
    @State private var addChildParent: Notes? = nil

    var body: some View {
        List {
            let untagged = vm.rootNotes(forTag: "None")
            if !untagged.isEmpty {
                ForEach(untagged) { root in
                    NoteTreeRow(
                        node: root,
                        depth: 0,
                        expanded: $expanded,
                        selectedNote: $selectedNote,
                        addChildParent: $addChildParent
                    )
                }
            }

            ForEach(vm.tags, id: \.self) { tag in
                Section(tag) {
                    ForEach(vm.rootNotes(forTag: tag)) { root in
                        NoteTreeRow(
                            node: root,
                            depth: 0,
                            expanded: $expanded,
                            selectedNote: $selectedNote,
                            addChildParent: $addChildParent
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .sheet(item: $selectedNote) { noteItem in
            ModalPreference(note: noteItem)
                .environmentObject(vm)
                .presentationDetents([.medium])
        }
        .fullScreenCover(item: $addChildParent) { parent in
            ChildCreationCover(parent: parent)
                .environmentObject(vm)
        }
    }
}

// MARK: - Recursive Tree Row
struct NoteTreeRow: View {
    let node: Notes
    let depth: Int
    @Binding var expanded: Set<UUID>
    @Binding var selectedNote: Notes?
    @Binding var addChildParent: Notes?
    @EnvironmentObject var vm: NotesViewModel

    private var isExpanded: Bool { expanded.contains(node.id) }
    private var hasChildren: Bool { !node.children.isEmpty }

    var body: some View {
        row
        if isExpanded {
            ForEach(node.children) { child in
                NoteTreeRow(
                    node: child,
                    depth: depth + 1,
                    expanded: $expanded,
                    selectedNote: $selectedNote,
                    addChildParent: $addChildParent
                )
            }
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            if hasChildren {
                Button {
                    if isExpanded { expanded.remove(node.id) } else { expanded.insert(node.id) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }

            NavigationLink(
                destination: NoteDetailView(note: node, tagsArray: .constant(vm.tags)) { updatedTitle, updatedText, updatedTag in
                    var updatedNote = node
                    updatedNote.title = updatedTitle
                    updatedNote.body = updatedText
                    updatedNote.tag = updatedTag
                    vm.update(updatedNote)
                }
            ) {
                UIComponents.NoteCell(note: node)
            }
            .buttonStyle(.plain)

            Button {
                addChildParent = node
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(depth) * 16)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                vm.deleteAndPromoteChildren(node)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                selectedNote = node
            } label: {
                Label("Preferences", systemImage: "wrench")
            }
        }
    }
}

// MARK: - Add Child Note
struct ChildCreationCover: View {
    @EnvironmentObject var vm: NotesViewModel
    let parent: Notes

    var body: some View {
        NoteCreationView(
            onSave: { title, body, tag in
                let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                let child = Notes(
                    id: UUID(),
                    title: title,
                    body: body,
                    parentId: parent.id,
                    children: [],
                    lastUpdated: Date(),
                    userID: 0,
                    colorHex: parent.colorHex ?? "#007BFF",
                    tag: trimmedTag.isEmpty ? (parent.tag ?? "") : tag
                )
                vm.add(child)
            },
            existingTags: vm.getTags(),
            initialTag: parent.tag ?? ""
        )
    }
}

// MARK: - Modal Preferences
struct ModalPreference: View {
    @EnvironmentObject var vm: NotesViewModel
    @State private var note: Notes

    init(note: Notes) {
        _note = State(initialValue: note)
    }

    private var possibleParents: [Notes] {
        let banned = vm.descendantIds(of: note.id).union([note.id])
        return vm.notes.filter { !banned.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Visualistics") {
                    Picker("Note Appearance", selection: Binding(
                        get: { note.colorHex ?? "#007BFF" },
                        set: { newColor in
                            note.colorHex = newColor
                            vm.update(note)
                        }
                    )) {
                        Text("Blue").tag("#007BFF")
                        Text("Red").tag("#DC3545")
                        Text("Green").tag("#28A745")
                        Text("Purple").tag("#6F42C1")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Parent Note") {
                    Picker("Parent Node", selection: Binding(
                        get: { note.parentId },
                        set: { newParentId in
                            note.parentId = newParentId
                            if let pid = newParentId, let parent = vm.notes.first(where: { $0.id == pid }) {
                                note.colorHex = parent.colorHex ?? note.colorHex
                                note.tag = parent.tag ?? note.tag
                            }
                            vm.update(note)
                        }
                    )) {
                        Text("None").tag(UUID?.none)
                        ForEach(possibleParents) { parent in
                            Text(parent.title).tag(Optional(parent.id))
                        }
                    }
                }
                TagPreference(note: $note)
            }
            .navigationTitle("Preferences")
        }
    }
}

struct TagPreference: View {
    @EnvironmentObject var vm: NotesViewModel
    @Binding var note : Notes

    var body: some View {
        Section("Tag") {
            Picker("Node", selection: Binding(
                get: {note.tag ?? ""},
                set: {newTag in
                    note.tag = newTag
                    vm.update(note)
                }
            )) {
                Text("None").tag("")
                ForEach(vm.getTags(), id: \.self) { tag in
                    Text(tag).tag(tag)
                }
            }
        }
    }
}

// MARK: - Note Detail View
struct NoteDetailView: View {
    let note: Notes
    @Binding var tagsArray: [String]

    @State var title: String
    @State var text: String
    @State var tag: String = ""


    var onSave: ((String, String, String) -> Void)?

    init(note: Notes, tagsArray: Binding<[String]>, onSave: ((String, String, String) -> Void)? = nil) {
        self.note = note
        self._tagsArray = tagsArray
        _title = State(initialValue: note.title)
        _text = State(initialValue: note.body)
        _tag = State(initialValue: note.tag ?? "")
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TagSelection(existingTags: tagsArray, tag: $tag)
                    .onChange(of: tag) { oldValue, newValue in
                        onSave?(title, text, newValue)
                    }

                TextField("Title", text: $title, axis: .vertical)
                    .font(.largeTitle.bold())
                    .textInputAutocapitalization(.never)
                    .onChange(of: title) { oldValue, newValue in
                        onSave?(newValue, text, tag)
                    }

                TextEditor(text: $text)
                    .font(.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 400)
                    .onChange(of: text) { oldValue, newValue in
                        onSave?(title, newValue, tag)
                    }
            }
            .padding()
        }
        .navigationTitle(title.isEmpty ? "Untitled" : title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Note Button
struct NoteAdd: View {
    @EnvironmentObject var vm: NotesViewModel
    @State private var showNoteCreation = false
    var onNoteAdded: (() -> Void)?

    var body: some View {
        VStack {
            Button {
                showNoteCreation = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
            }
            .fullScreenCover(isPresented: $showNoteCreation) {
                NoteCreationView(
                    onSave: { title, body, tag in
                        let note = Notes(
                            id: UUID(),
                            title: title,
                            body: body,
                            parentId: nil,
                            children: [],
                            lastUpdated: Date(),
                            userID: 0,
                            colorHex: "#007BFF",
                            tag: tag
                        )
                        vm.add(note)
                        onNoteAdded?()
                    },
                    existingTags: vm.getTags()
                )
            }
        }
    }
}

// MARK: - Note Creation View
struct NoteCreationView: View {
    @Environment(\.dismiss) var dismiss
    @State var title: String = ""
    @State var text: String = ""
    @State var tag: String = ""
    var onSave: (String, String, String) -> Void
    var existingTags : [String]

    init(onSave: @escaping (String, String, String) -> Void, existingTags: [String], initialTag: String = "") {
        self.onSave = onSave
        self.existingTags = existingTags
        _tag = State(initialValue: initialTag)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: save) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline)
                }
                Spacer()
            }
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TagSelection(existingTags: existingTags, tag: $tag)

                    TextField("Title", text: $title, axis: .vertical)
                        .font(.largeTitle.bold())
                        .textInputAutocapitalization(.never)

                    TextEditor(text: $text)
                        .font(.body)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 400)
                }
                .padding()
            }
        }
    }

    private func save() {
        if title.isEmpty && text.isEmpty { dismiss(); return }
        onSave(title, text, tag)
        dismiss()
    }
}

struct TagSelection: View {
    var existingTags : [String]
    @Binding var tag: String

    @State private var showNewTagAlert = false
    @State private var newTagName = ""

    var body: some View {
        Menu {
            ForEach(existingTags, id: \.self) { candidate in
                Button {
                    tag = candidate
                } label: {
                    if candidate == tag {
                        Label(candidate, systemImage: "checkmark")
                    } else {
                        Text(candidate)
                    }
                }
            }
            if !existingTags.isEmpty { Divider() }
            Button {
                newTagName = ""
                showNewTagAlert = true
            } label: {
                Label("New Tag…", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                Text(tag.isEmpty ? "Add tag" : tag)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(tag.isEmpty ? .secondary : .primary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.systemGray6), in: Capsule())
        }
        .alert("New Tag", isPresented: $showNewTagAlert) {
            TextField("Tag name", text: $newTagName)
            Button("Add", action: commitNewTag)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func commitNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tag = trimmed
    }
}

struct NoteView_Previews: PreviewProvider {
    static var previews: some View {
        NoteView(selectedTab: .constant(.notes))
    }
}
