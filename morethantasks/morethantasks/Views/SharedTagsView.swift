//  SharedTagsView.swift
//  Lists tags shared with this user, each expandable into the owner's note
//  tree for that tag. Kept as its own screen (not folded into NoteListView's
//  own tag sections) so a shared tag never mixes with a same-named tag of
//  this user's own -- see SharedTagsViewModel's header comment.
import SwiftUI

struct SharedTagsView: View {
    @StateObject private var vm = SharedTagsViewModel()
    @State private var expandedTagIds: Set<String> = []

    var body: some View {
        Group {
            if vm.sharedTags.isEmpty {
                ContentUnavailableView("No Shared Tags", systemImage: "tag",
                                        description: Text("Tags others share with you will show up here."))
            } else {
                List {
                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage).foregroundColor(.red).font(.footnote)
                    }
                    ForEach(vm.sharedTags) { tag in
                        DisclosureGroup(isExpanded: Binding(
                            get: { expandedTagIds.contains(tag.id) },
                            set: { isOpen in
                                if isOpen {
                                    expandedTagIds.insert(tag.id)
                                    Task { await vm.loadNotes(forTag: tag.id) }
                                } else {
                                    expandedTagIds.remove(tag.id)
                                }
                            }
                        )) {
                            ForEach(vm.rootNotes(forTag: tag.id)) { root in
                                SharedNoteTreeRow(node: root, depth: 0, vm: vm)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tag.name).font(.headline)
                                Text("Shared by \(tag.ownerEmail)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Shared Tags")
        .task { await vm.loadSharedTags() }
    }
}

private struct SharedNoteTreeRow: View {
    let node: Notes
    let depth: Int
    @ObservedObject var vm: SharedTagsViewModel

    var body: some View {
        NavigationLink(destination: SharedNoteDetailView(note: node, vm: vm)) {
            UIComponents.NoteCell(note: node)
        }
        .padding(.leading, CGFloat(depth) * 16)

        ForEach(node.children) { child in
            SharedNoteTreeRow(node: child, depth: depth + 1, vm: vm)
        }
    }
}

private struct SharedNoteDetailView: View {
    let note: Notes
    @ObservedObject var vm: SharedTagsViewModel

    var body: some View {
        NoteDetailView(note: note, tagsArray: .constant([])) { updatedTitle, updatedText, updatedTag in
            var updated = note
            updated.title = updatedTitle
            updated.body = updatedText
            updated.tag = updatedTag
            Task { await vm.updateNoteMetadata(updated) }
        }
    }
}
