//  RGAConvergenceTests.swift
import Testing
import Foundation
@testable import morethantasks

struct RGAConvergenceTests {

    // Build a fixed pool of ops from two sites, then apply that SAME pool in
    // many random orders. Every resulting document must have identical text.
    // If merge logic is order-dependent (a real RGA bug), this fails.
    @Test func randomOrderingsConverge() {
        let siteA = UUID(); let siteB = UUID()
        // Site A types "hello"; Site B types "world" at the start, concurrently.
        var ops: [RGAOp] = []
        var prevA: CharID? = nil
        for (i, ch) in "hello".enumerated() {
            let id = CharID(lamport: UInt64(i + 1), siteId: siteA)
            ops.append(RGAOp(type: .insert, id: id, parentId: prevA, char: String(ch)))
            prevA = id
        }
        var prevB: CharID? = nil
        for (i, ch) in "world".enumerated() {
            let id = CharID(lamport: UInt64(i + 1), siteId: siteB)
            ops.append(RGAOp(type: .insert, id: id, parentId: prevB, char: String(ch)))
            prevB = id
        }

        // Reference result from applying in pool order.
        let reference = RGADocument()
        ops.forEach { reference.apply($0) }
        let expected = reference.text()
        #expect(expected.count == 10)   // all chars present, none lost

        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let doc = RGADocument()
            ops.shuffled(using: &rng).forEach { doc.apply($0) }
            #expect(doc.text() == expected)
        }
    }

    // Same invariant, but with deletes mixed in.
    @Test func randomOrderingsWithDeletesConverge() {
        let site = UUID()
        var ops: [RGAOp] = []
        var prev: CharID? = nil
        var ids: [CharID] = []
        for (i, ch) in "abcdef".enumerated() {
            let id = CharID(lamport: UInt64(i + 1), siteId: site)
            ops.append(RGAOp(type: .insert, id: id, parentId: prev, char: String(ch)))
            ids.append(id); prev = id
        }
        // Delete "c" and "e".
        ops.append(RGAOp(type: .delete, id: ids[2], parentId: nil, char: nil))
        ops.append(RGAOp(type: .delete, id: ids[4], parentId: nil, char: nil))

        let reference = RGADocument()
        ops.forEach { reference.apply($0) }
        let expected = reference.text()
        #expect(expected == "abdf")

        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let doc = RGADocument()
            ops.shuffled(using: &rng).forEach { doc.apply($0) }
            #expect(doc.text() == expected)
        }
    }

    // Two sites each insert one char at the SAME position (after the same
    // parent), offline. Both must converge to the same order, decided by id.
    @Test func concurrentInsertSamePositionIsDeterministic() {
        let siteA = UUID(); let siteB = UUID()
        let base = CharID(lamport: 1, siteId: siteA)
        let baseOp = RGAOp(type: .insert, id: base, parentId: nil, char: "X")
        // Both insert after base at lamport 2; tie-break decides order.
        let aOp = RGAOp(type: .insert, id: CharID(lamport: 2, siteId: siteA), parentId: base, char: "A")
        let bOp = RGAOp(type: .insert, id: CharID(lamport: 2, siteId: siteB), parentId: base, char: "B")

        let doc1 = RGADocument()
        [baseOp, aOp, bOp].forEach { doc1.apply($0) }
        let doc2 = RGADocument()
        [baseOp, bOp, aOp].forEach { doc2.apply($0) }   // reverse arrival

        #expect(doc1.text() == doc2.text())
        // Higher siteId string sorts later in CharID.< → renders LATER among
        // descending siblings, i.e. closer to base. Either way both agree:
        #expect(doc1.text().count == 3)
    }

    // Simulate two clients editing offline, then exchanging all ops. Both must
    // converge to identical text — including a delete racing an insert.
    @Test func twoReplicasConvergeAfterExchange() {
        let docA = RGADocument(); let edA = RGAEditor(document: docA, siteId: UUID())
        let docB = RGADocument(); let edB = RGAEditor(document: docB, siteId: UUID())

        // Shared starting point: both apply the same seed ops.
        let seed = edA.applyLocalChange(from: "", to: "shared")
        seed.forEach { docB.apply($0) }
        #expect(docB.text() == "shared")

        // Offline divergence: A appends, B deletes the first char concurrently.
        let aOps = edA.applyLocalChange(from: "shared", to: "shared!")   // insert "!"
        let bOps = edB.applyLocalChange(from: "shared", to: "hared")     // delete "s"

        // Exchange.
        bOps.forEach { docA.apply($0) }
        aOps.forEach { docB.apply($0) }

        // Converged and reflects both edits: "s" gone, "!" added → "hared!".
        #expect(docA.text() == docB.text())
        #expect(docA.text() == "hared!")
    }
}
