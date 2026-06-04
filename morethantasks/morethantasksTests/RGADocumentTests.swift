//  RGADocumentTests.swift
import Testing
import Foundation
@testable import morethantasks

struct RGADocumentTests {
    // An op must survive JSON encode/decode unchanged — it is the sync wire format.
    @Test func opCodableRoundTrip() throws {
        let id = CharID(lamport: 3, siteId: UUID())
        let op = RGAOp(type: .insert, id: id, parentId: nil, char: "x")
        let data = try JSONEncoder().encode(op)
        let back = try JSONDecoder().decode(RGAOp.self, from: data)
        #expect(back == op)
    }

    // Helper to mint deterministic ids for a single "site" in tests.
    private func site() -> (UInt64) -> CharID {
        let s = UUID()
        return { lamport in CharID(lamport: lamport, siteId: s) }
    }

    // Typing "ab" left to right: b is inserted after a.
    @Test func insertSequentialProducesText() {
        let id = site()
        let doc = RGADocument()
        let a = id(1); let b = id(2)
        doc.apply(RGAOp(type: .insert, id: a, parentId: nil, char: "a"))
        doc.apply(RGAOp(type: .insert, id: b, parentId: a, char: "b"))
        #expect(doc.text() == "ab")
    }

    // Inserting "c" after a (between a and b) yields "acb": c has a higher id
    // than b, so among a's children c (higher) renders before b (lower).
    @Test func insertBetweenOrdersByDescendingId() {
        let id = site()
        let doc = RGADocument()
        let a = id(1); let b = id(2); let c = id(3)
        doc.apply(RGAOp(type: .insert, id: a, parentId: nil, char: "a"))
        doc.apply(RGAOp(type: .insert, id: b, parentId: a, char: "b"))
        doc.apply(RGAOp(type: .insert, id: c, parentId: a, char: "c"))
        #expect(doc.text() == "acb")
    }

    // Deleting an element removes it from the text but keeps it as an anchor.
    @Test func deleteRemovesFromText() {
        let id = site()
        let doc = RGADocument()
        let a = id(1); let b = id(2); let c = id(3)
        doc.apply(RGAOp(type: .insert, id: a, parentId: nil, char: "a"))
        doc.apply(RGAOp(type: .insert, id: b, parentId: a, char: "b"))
        doc.apply(RGAOp(type: .insert, id: c, parentId: b, char: "c"))
        doc.apply(RGAOp(type: .delete, id: b, parentId: nil, char: nil))
        #expect(doc.text() == "ac")   // b tombstoned; c still anchored after b
    }

    // Applying the same insert twice must not duplicate the character.
    @Test func duplicateInsertIsNoOp() {
        let id = site()
        let doc = RGADocument()
        let a = id(1)
        let op = RGAOp(type: .insert, id: a, parentId: nil, char: "a")
        doc.apply(op)
        doc.apply(op)
        #expect(doc.text() == "a")
    }

    // Applying the same delete twice is a no-op.
    @Test func duplicateDeleteIsNoOp() {
        let id = site()
        let doc = RGADocument()
        let a = id(1); let b = id(2)
        doc.apply(RGAOp(type: .insert, id: a, parentId: nil, char: "a"))
        doc.apply(RGAOp(type: .insert, id: b, parentId: a, char: "b"))
        let del = RGAOp(type: .delete, id: b, parentId: nil, char: nil)
        doc.apply(del)
        doc.apply(del)
        #expect(doc.text() == "a")
    }

    // An insert whose parent has not arrived yet must wait, then apply once it does.
    @Test func insertBeforeParentBuffersThenApplies() {
        let id = site()
        let doc = RGADocument()
        let a = id(1); let b = id(2)
        // Child b arrives before parent a.
        doc.apply(RGAOp(type: .insert, id: b, parentId: a, char: "b"))
        #expect(doc.text() == "")          // buffered, not visible yet
        doc.apply(RGAOp(type: .insert, id: a, parentId: nil, char: "a"))
        #expect(doc.text() == "ab")        // parent landed → child flushed
    }

    // A delete arriving before its target insert must wait, then tombstone it.
    @Test func deleteBeforeInsertBuffersThenApplies() {
        let id = site()
        let doc = RGADocument()
        let a = id(1); let b = id(2)
        doc.apply(RGAOp(type: .insert, id: a, parentId: nil, char: "a"))
        doc.apply(RGAOp(type: .delete, id: b, parentId: nil, char: nil))  // target b absent
        doc.apply(RGAOp(type: .insert, id: b, parentId: a, char: "b"))    // b arrives
        #expect(doc.text() == "a")         // b was tombstoned on arrival
    }
}
