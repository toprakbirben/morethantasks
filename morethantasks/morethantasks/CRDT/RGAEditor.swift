//  RGAEditor.swift
//  Pure translation from a whole-string text change (as delivered by SwiftUI's
//  TextEditor) into CRDT ops, applied to the document. No UI, no networking.
//
//  Strategy: find the common prefix and common suffix of old vs new text; the
//  middle that differs becomes deletes (for removed chars, by their element id)
//  plus a chain of inserts (for added chars, anchored after the last surviving
//  prefix element).
import Foundation

final class RGAEditor {
    let document: RGADocument
    private let siteId: UUID

    init(document: RGADocument, siteId: UUID) {
        self.document = document
        self.siteId = siteId
    }

    @discardableResult
    func applyLocalChange(from old: String, to new: String) -> [RGAOp] {
        let oldChars = Array(old)
        let newChars = Array(new)

        // Element ids in current visible order — parallel to `oldChars`.
        let ids = document.orderedVisibleElements()
        // Defensive: if the document's visible text drifted from `old`, fall
        // back to treating everything as a replace of the whole document.
        let prefixCap = min(oldChars.count, newChars.count)

        var prefix = 0
        while prefix < prefixCap && oldChars[prefix] == newChars[prefix] { prefix += 1 }

        var suffix = 0
        while suffix < (prefixCap - prefix)
            && oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }

        var ops: [RGAOp] = []

        // Deletes: old[prefix ..< oldCount - suffix]
        let delLower = prefix
        let delUpper = oldChars.count - suffix
        if delLower < delUpper && delUpper <= ids.count {
            for i in delLower..<delUpper {
                ops.append(RGAOp(type: .delete, id: ids[i], parentId: nil, char: nil))
            }
        }

        // Inserts: new[prefix ..< newCount - suffix], chained after the element
        // at (prefix - 1), or document start if prefix == 0.
        var anchor: CharID? = (prefix > 0 && prefix - 1 < ids.count) ? ids[prefix - 1] : nil
        let insLower = prefix
        let insUpper = newChars.count - suffix
        if insLower < insUpper {
            for i in insLower..<insUpper {
                let id = CharID(lamport: document.lamport + 1, siteId: siteId)
                let op = RGAOp(type: .insert, id: id, parentId: anchor, char: String(newChars[i]))
                ops.append(op)
                document.apply(op)        // apply insert immediately so lamport advances
                anchor = id
            }
        }

        // Apply deletes after inserts (order doesn't matter for correctness).
        for op in ops where op.type == .delete { document.apply(op) }

        return ops
    }
}
