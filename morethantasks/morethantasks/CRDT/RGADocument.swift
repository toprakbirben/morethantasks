//  RGADocument.swift
//  Conflict-free plain-text sequence CRDT, modelled as a tree.
//  Each element's parentId is the element it was inserted AFTER (nil = start).
//  Siblings render in DESCENDING CharID order. Visible text is an iterative
//  pre-order traversal. Applying the same set of ops in any order yields the
//  same tree, hence the same text — that is the convergence guarantee.
import Foundation

final class RGADocument {

    private struct Element {
        let id: CharID
        let parentId: CharID?
        let char: Character
        var deleted: Bool
    }

    private var elements: [CharID: Element] = [:]
    // Child ids per parent, kept sorted DESCENDING. nil key = root children.
    private var children: [CharID?: [CharID]] = [:]

    // Ops waiting for a missing dependency (insert: parent absent; delete:
    // target absent). Keyed by the missing CharID; flushed when it arrives.
    private var pending: [CharID: [RGAOp]] = [:]

    // Logical clock: max id Lamport seen, so locally-minted ids stay causal.
    private(set) var lamport: UInt64 = 0

    init() {}

    // MARK: - Apply

    func apply(_ op: RGAOp) {
        lamport = max(lamport, op.id.lamport)
        switch op.type {
        case .insert:
            applyInsert(op)
        case .delete:
            applyDelete(op)
        }
    }

    private func applyInsert(_ op: RGAOp) {
        guard elements[op.id] == nil else { return }            // idempotent
        if let parent = op.parentId, elements[parent] == nil {
            pending[parent, default: []].append(op)             // wait for parent
            return
        }
        guard let charStr = op.char, let ch = charStr.first else { return }
        elements[op.id] = Element(id: op.id, parentId: op.parentId, char: ch, deleted: false)
        insertChild(op.id, under: op.parentId)
        flushPending(dependingOn: op.id)
    }

    private func applyDelete(_ op: RGAOp) {
        guard let existing = elements[op.id] else {
            pending[op.id, default: []].append(op)              // wait for target insert
            return
        }
        if existing.deleted { return }                          // idempotent
        var e = existing
        e.deleted = true
        elements[op.id] = e
    }

    // Re-apply any ops that were waiting on `id` now that it exists.
    private func flushPending(dependingOn id: CharID) {
        guard let waiting = pending.removeValue(forKey: id) else { return }
        for op in waiting { apply(op) }
    }

    // Insert `id` into its parent's child list, keeping DESCENDING order.
    private func insertChild(_ id: CharID, under parent: CharID?) {
        var siblings = children[parent] ?? []
        // find first index whose id is LESS than `id`; insert before it.
        var lo = 0, hi = siblings.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if siblings[mid] > id { lo = mid + 1 } else { hi = mid }
        }
        siblings.insert(id, at: lo)
        children[parent] = siblings
    }

    // MARK: - Read

    func text() -> String {
        String(orderedVisibleElements().map { elements[$0]!.char })
    }

    // Visible (non-deleted) element ids in document order. Iterative pre-order
    // (explicit stack) so a long linear chain cannot overflow the call stack.
    func orderedVisibleElements() -> [CharID] {
        var out: [CharID] = []
        // Push root children in ascending order so the highest pops first
        // (LIFO) → descending visit order.
        var stack: [CharID] = (children[nil] ?? []).reversed()
        while let id = stack.popLast() {
            let e = elements[id]!
            if !e.deleted { out.append(id) }
            if let kids = children[id] { stack.append(contentsOf: kids.reversed()) }
        }
        return out
    }
}
