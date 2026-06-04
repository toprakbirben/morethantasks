//  RGAEditorTests.swift
import Testing
import Foundation
@testable import morethantasks

struct RGAEditorTests {
    private func makeEditor() -> RGAEditor {
        RGAEditor(document: RGADocument(), siteId: UUID())
    }

    // Typing from empty produces text equal to the input.
    @Test func typeFromEmpty() {
        let ed = makeEditor()
        ed.applyLocalChange(from: "", to: "hello")
        #expect(ed.document.text() == "hello")
    }

    // Appending a character.
    @Test func appendChar() {
        let ed = makeEditor()
        ed.applyLocalChange(from: "", to: "ab")
        ed.applyLocalChange(from: "ab", to: "abc")
        #expect(ed.document.text() == "abc")
    }

    // Inserting in the middle.
    @Test func insertMiddle() {
        let ed = makeEditor()
        ed.applyLocalChange(from: "", to: "ac")
        ed.applyLocalChange(from: "ac", to: "abc")
        #expect(ed.document.text() == "abc")
    }

    // Deleting from the middle.
    @Test func deleteMiddle() {
        let ed = makeEditor()
        ed.applyLocalChange(from: "", to: "abc")
        ed.applyLocalChange(from: "abc", to: "ac")
        #expect(ed.document.text() == "ac")
    }

    // Replacing a span (delete + insert at once).
    @Test func replaceSpan() {
        let ed = makeEditor()
        ed.applyLocalChange(from: "", to: "hello")
        ed.applyLocalChange(from: "hello", to: "help")
        #expect(ed.document.text() == "help")
    }

    // Generated ops are returned so the caller can enqueue them for sync.
    @Test func returnsGeneratedOps() {
        let ed = makeEditor()
        let ops = ed.applyLocalChange(from: "", to: "hi")
        #expect(ops.count == 2)
        #expect(ops.allSatisfy { $0.type == .insert })
    }

    // Fuzz: from a random current text, apply a random next text via the diff;
    // the document must end up exactly equal to the next text. This guards the
    // riskiest unit — the diff→ops translation — against silent corruption.
    @Test func fuzzDiffReproducesTarget() {
        let alphabet = Array("abc")   // small alphabet → frequent collisions
        var rng = SystemRandomNumberGenerator()

        func randomText() -> String {
            let n = Int.random(in: 0...8, using: &rng)
            return String((0..<n).map { _ in alphabet.randomElement(using: &rng)! })
        }

        for _ in 0..<500 {
            let ed = RGAEditor(document: RGADocument(), siteId: UUID())
            var current = ""
            // Walk through several edits, asserting convergence at each step.
            for _ in 0..<5 {
                let next = randomText()
                ed.applyLocalChange(from: current, to: next)
                #expect(ed.document.text() == next)
                current = next
            }
        }
    }
}
