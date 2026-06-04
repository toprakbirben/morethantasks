# Collaborative Editing — Phase 1: RGA Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pure-Swift, conflict-free, plain-text sequence CRDT (RGA) that merges concurrent edits to a note body deterministically, with full convergence tests — and nothing else (no networking, storage, or UI).

**Architecture:** The document is a **tree**. Each character element records the element it was inserted *after* as its `parentId` (nil = start of document). Siblings sharing a parent are ordered by **descending `CharID`**. The visible text is an **iterative pre-order traversal** of the tree. Because the tree is a pure function of the set of `(id, parentId)` pairs, applying the same ops in any order yields the same tree — this is the convergence guarantee. Out-of-order ops (a child before its parent, a delete before its insert) wait in a pending buffer until their dependency arrives. All ops are idempotent.

**Tech Stack:** Swift, Swift Testing framework (`import Testing`, `@Test`, `#expect`). No third-party dependencies. Target: the existing `morethantasks` app + `morethantasksTests` test target.

**Spec:** `docs/superpowers/specs/2026-06-02-collaborative-editing-design.md` (Section 2, Section 5 tests 1–4).

---

## Conventions for this plan

- **Project root** (where `morethantasks.xcodeproj` lives): `/Users/toprakbirben/projects/mtt/morethantasks/`. All paths below are relative to it.
- **App source** goes in `morethantasks/CRDT/`. **Tests** go in `morethantasksTests/`.
- **Adding files to the Xcode targets:** This project may use Xcode file-system-synchronized groups, in which case files dropped into the folders are picked up automatically. If a new `.swift` file is not compiled (e.g. "cannot find type in scope" at build), open the project in Xcode and add the file to the `morethantasks` target (engine files) or `morethantasksTests` target (test files) via File Inspector → Target Membership.
- **Run tests** (adjust the simulator name to one installed locally, e.g. `iPhone 16`):
  ```bash
  cd /Users/toprakbirben/projects/mtt/morethantasks
  xcodebuild test -scheme morethantasks \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:morethantasksTests/<Suite> 2>&1 | tail -30
  ```
  To run a single test: `-only-testing:morethantasksTests/<Suite>/<testFunc>`.
- **Commit cadence:** one commit per task (after its tests pass). Branch: `feature/collaborative-editing` (already created).

---

## File structure (created in this phase)

- `morethantasks/CRDT/CharID.swift` — element identity + total order.
- `morethantasks/CRDT/RGAOp.swift` — the insert/delete operation value type.
- `morethantasks/CRDT/RGADocument.swift` — the CRDT engine: apply ops, materialize text, pending buffer.
- `morethantasks/CRDT/RGAEditor.swift` — pure text-diff → ops translator (no UI).
- `morethantasksTests/CharIDTests.swift`
- `morethantasksTests/RGADocumentTests.swift`
- `morethantasksTests/RGAConvergenceTests.swift`
- `morethantasksTests/RGAEditorTests.swift`

Each file has one responsibility. `RGADocument` knows nothing about diffing; `RGAEditor` knows nothing about networking or SwiftUI.

---

## Task 1: CharID — element identity and total order

**Files:**
- Create: `morethantasks/CRDT/CharID.swift`
- Test: `morethantasksTests/CharIDTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//  CharIDTests.swift
import Testing
import Foundation
@testable import morethantasks

struct CharIDTests {
    // A lower Lamport clock always sorts earlier, regardless of site.
    @Test func lowerLamportSortsFirst() {
        let a = CharID(lamport: 1, siteId: UUID())
        let b = CharID(lamport: 2, siteId: UUID())
        #expect(a < b)
    }

    // Equal Lamport clocks tie-break deterministically on siteId string.
    @Test func equalLamportTieBreaksOnSite() {
        let lo = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let hi = UUID(uuidString: "FF000000-0000-0000-0000-000000000000")!
        let a = CharID(lamport: 5, siteId: lo)
        let b = CharID(lamport: 5, siteId: hi)
        #expect(a < b)
        #expect(!(b < a))
    }

    // Total order: the tie-break makes any two distinct ids comparable.
    @Test func distinctIdsAreOrdered() {
        let a = CharID(lamport: 5, siteId: UUID())
        let b = CharID(lamport: 5, siteId: UUID())
        #expect((a < b) || (b < a))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /Users/toprakbirben/projects/mtt/morethantasks
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/CharIDTests 2>&1 | tail -20
```
Expected: build failure — `cannot find 'CharID' in scope`.

- [ ] **Step 3: Write the minimal implementation**

```swift
//  CharID.swift
//  Globally-unique, totally-ordered identity for a single character element.
//  lamport: logical clock (see RGADocument). siteId: stable per-installation id.
import Foundation

struct CharID: Comparable, Hashable, Codable {
    let lamport: UInt64
    let siteId: UUID

    static func < (lhs: CharID, rhs: CharID) -> Bool {
        if lhs.lamport != rhs.lamport { return lhs.lamport < rhs.lamport }
        return lhs.siteId.uuidString < rhs.siteId.uuidString
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run the Step 2 command. Expected: all three tests PASS.

- [ ] **Step 5: Commit**

```bash
git add morethantasks/CRDT/CharID.swift morethantasksTests/CharIDTests.swift
git commit -m "feat(crdt): CharID identity with total ordering"
```

---

## Task 2: RGAOp — the operation value type

**Files:**
- Create: `morethantasks/CRDT/RGAOp.swift`
- Test: (covered indirectly; add a Codable round-trip test here)
- Test file: `morethantasksTests/RGADocumentTests.swift` (created now, grows in later tasks)

- [ ] **Step 1: Write the failing test**

```swift
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
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /Users/toprakbirben/projects/mtt/morethantasks
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/RGADocumentTests 2>&1 | tail -20
```
Expected: build failure — `cannot find 'RGAOp' in scope`.

- [ ] **Step 3: Write the minimal implementation**

```swift
//  RGAOp.swift
//  One CRDT operation. insert: a new element `id` placed after `parentId`
//  (nil = document start) carrying `char`. delete: tombstone the element `id`
//  (parentId/char are nil for deletes). Codable — this is the sync wire format.
import Foundation

enum RGAOpType: String, Codable {
    case insert
    case delete
}

struct RGAOp: Codable, Hashable {
    let type: RGAOpType
    let id: CharID
    let parentId: CharID?
    let char: String?   // single character; non-nil only for inserts
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run the Step 2 command. Expected: `opCodableRoundTrip` PASSES.

- [ ] **Step 5: Commit**

```bash
git add morethantasks/CRDT/RGAOp.swift morethantasksTests/RGADocumentTests.swift
git commit -m "feat(crdt): RGAOp wire-format value type"
```

---

## Task 3: RGADocument — insert + materialize (the tree core)

**Files:**
- Create: `morethantasks/CRDT/RGADocument.swift`
- Test: `morethantasksTests/RGADocumentTests.swift` (add tests)

- [ ] **Step 1: Write the failing tests**

Add to `RGADocumentTests`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd /Users/toprakbirben/projects/mtt/morethantasks
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/RGADocumentTests 2>&1 | tail -20
```
Expected: build failure — `cannot find 'RGADocument' in scope`.

- [ ] **Step 3: Write the minimal implementation**

```swift
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
        guard let charStr = op.char, let ch = charStr.first else { return }
        elements[op.id] = Element(id: op.id, parentId: op.parentId, char: ch, deleted: false)
        insertChild(op.id, under: op.parentId)
    }

    private func applyDelete(_ op: RGAOp) {
        guard var e = elements[op.id] else { return }
        if e.deleted { return }                                 // idempotent
        e.deleted = true
        elements[op.id] = e
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
```

> Note: `children[parent]` is stored descending; `.reversed()` gives ascending, and `popLast()` (LIFO) then visits descending — and a popped node's children are pushed immediately, giving correct pre-order.

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command. Expected: `insertSequentialProducesText` and `insertBetweenOrdersByDescendingId` PASS.

- [ ] **Step 5: Commit**

```bash
git add morethantasks/CRDT/RGADocument.swift morethantasksTests/RGADocumentTests.swift
git commit -m "feat(crdt): RGADocument insert + iterative materialize"
```

---

## Task 4: RGADocument — delete (tombstone)

**Files:**
- Modify: `morethantasks/CRDT/RGADocument.swift` (already supports delete from Task 3; this task proves it)
- Test: `morethantasksTests/RGADocumentTests.swift` (add tests)

- [ ] **Step 1: Write the failing tests**

Add to `RGADocumentTests`:
```swift
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
```

- [ ] **Step 2: Run the test to verify it fails or passes**

Run:
```bash
cd /Users/toprakbirben/projects/mtt/morethantasks
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/RGADocumentTests/deleteRemovesFromText 2>&1 | tail -20
```
Expected: PASS (delete was implemented in Task 3; this test pins the tombstone-as-anchor behavior so a future refactor can't silently break it).

- [ ] **Step 3: No new implementation needed**

The delete path and "tombstone still anchors children" behavior already exist. If the test fails, the bug is that `orderedVisibleElements()` skips traversal into deleted nodes — ensure children of a deleted node are still pushed (the Task 3 code pushes children regardless of `deleted`, which is correct).

- [ ] **Step 4: Confirm green**

Re-run Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add morethantasksTests/RGADocumentTests.swift
git commit -m "test(crdt): delete tombstones char but keeps it as anchor"
```

---

## Task 5: RGADocument — idempotency

**Files:**
- Test: `morethantasksTests/RGADocumentTests.swift` (add tests)

- [ ] **Step 1: Write the failing tests**

Add to `RGADocumentTests`:
```swift
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
```

- [ ] **Step 2: Run the tests**

Run:
```bash
cd /Users/toprakbirben/projects/mtt/morethantasks
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/RGADocumentTests/duplicateInsertIsNoOp -only-testing:morethantasksTests/RGADocumentTests/duplicateDeleteIsNoOp 2>&1 | tail -20
```
Expected: PASS (the `guard elements[op.id] == nil` and `if e.deleted { return }` guards from Task 3 provide idempotency; these tests lock it in).

- [ ] **Step 3: No new implementation needed**

If a test fails, the dedupe guards in `applyInsert`/`applyDelete` are missing or wrong — restore them per Task 3.

- [ ] **Step 4: Confirm green**

Re-run Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add morethantasksTests/RGADocumentTests.swift
git commit -m "test(crdt): inserts and deletes are idempotent"
```

---

## Task 6: RGADocument — pending buffer for out-of-order ops

**Files:**
- Modify: `morethantasks/CRDT/RGADocument.swift`
- Test: `morethantasksTests/RGADocumentTests.swift` (add tests)

- [ ] **Step 1: Write the failing tests**

Add to `RGADocumentTests`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd /Users/toprakbirben/projects/mtt/morethantasks
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/RGADocumentTests/insertBeforeParentBuffersThenApplies -only-testing:morethantasksTests/RGADocumentTests/deleteBeforeInsertBuffersThenApplies 2>&1 | tail -20
```
Expected: FAIL — without buffering, the early child renders as "b" (or the delete is dropped), so text assertions fail.

- [ ] **Step 3: Write the implementation**

Add a pending buffer and a flush loop. Replace `applyInsert` / `applyDelete` and add `pending` storage:

```swift
    // Ops waiting for a missing dependency (insert: parent absent; delete:
    // target absent). Keyed by the missing CharID; flushed when it arrives.
    private var pending: [CharID: [RGAOp]] = [:]

    private func applyInsert(_ op: RGAOp) {
        guard elements[op.id] == nil else { return }
        if let parent = op.parentId, elements[parent] == nil {
            pending[parent, default: []].append(op)   // wait for parent
            return
        }
        guard let charStr = op.char, let ch = charStr.first else { return }
        elements[op.id] = Element(id: op.id, parentId: op.parentId, char: ch, deleted: false)
        insertChild(op.id, under: op.parentId)
        flushPending(dependingOn: op.id)
    }

    private func applyDelete(_ op: RGAOp) {
        guard let existing = elements[op.id] else {
            pending[op.id, default: []].append(op)    // wait for target insert
            return
        }
        if existing.deleted { return }
        var e = existing
        e.deleted = true
        elements[op.id] = e
    }

    // Re-apply any ops that were waiting on `id` now that it exists.
    private func flushPending(dependingOn id: CharID) {
        guard let waiting = pending.removeValue(forKey: id) else { return }
        for op in waiting { apply(op) }
    }
```

> `flushPending` is called only after an insert lands. A delete that was waiting on `id` is keyed under `id` (the target), so it flushes when that target's insert arrives. An insert waiting on a parent is keyed under the parent, so it flushes when the parent arrives. Recursion via `apply` handles chains (grandchild waiting on child waiting on parent).

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command. Expected: both tests PASS. Then run the whole suite to confirm no regression:
```bash
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/RGADocumentTests 2>&1 | tail -20
```
Expected: all `RGADocumentTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add morethantasks/CRDT/RGADocument.swift morethantasksTests/RGADocumentTests.swift
git commit -m "feat(crdt): buffer out-of-order ops until dependencies arrive"
```

---

## Task 7: Convergence property test (the core invariant)

**Files:**
- Create: `morethantasksTests/RGAConvergenceTests.swift`

This is the test that justifies hand-rolling the CRDT: it encodes WHY the design is correct — any application order of the same op set must converge to identical text.

- [ ] **Step 1: Write the failing/passing test**

```swift
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
}
```

- [ ] **Step 2: Run the tests**

Run:
```bash
cd /Users/toprakbirben/projects/mtt/morethantasks
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/RGAConvergenceTests 2>&1 | tail -25
```
Expected: PASS. **If this fails**, do not paper over it — the merge/insertion rule is order-dependent and must be fixed in `RGADocument` (this is the whole correctness bet). Use superpowers:systematic-debugging.

- [ ] **Step 3: No new implementation (unless the test exposes a bug)**

If green, the engine converges. If red, fix `insertChild` / `orderedVisibleElements` / buffering until green.

- [ ] **Step 4: Confirm green**

Re-run Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add morethantasksTests/RGAConvergenceTests.swift
git commit -m "test(crdt): convergence under random op orderings (with deletes)"
```

---

## Task 8: Concurrent-insert determinism

**Files:**
- Modify: `morethantasksTests/RGAConvergenceTests.swift` (add test)

- [ ] **Step 1: Write the test**

Add to `RGAConvergenceTests`:
```swift
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
```

- [ ] **Step 2: Run the test**

Run:
```bash
cd /Users/toprakbirben/projects/mtt/morethantasks
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/RGAConvergenceTests/concurrentInsertSamePositionIsDeterministic 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 3: No new implementation expected**

If red, the sibling ordering in `insertChild` is not a pure function of id — fix until green.

- [ ] **Step 4: Confirm green**

Re-run Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add morethantasksTests/RGAConvergenceTests.swift
git commit -m "test(crdt): concurrent same-position inserts are deterministic"
```

---

## Task 9: RGAEditor — diff a text change into ops

**Files:**
- Create: `morethantasks/CRDT/RGAEditor.swift`
- Test: `morethantasksTests/RGAEditorTests.swift`

`RGAEditor` is the bridge between a whole-string `TextEditor` change and CRDT ops. It is pure: given the current document and (oldText → newText), it returns the ops to apply, and applies them. No UI, no I/O. This is the riskiest unit, so it is fuzz-tested in Task 10.

- [ ] **Step 1: Write the failing tests**

```swift
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
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd /Users/toprakbirben/projects/mtt/morethantasks
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/RGAEditorTests 2>&1 | tail -20
```
Expected: build failure — `cannot find 'RGAEditor' in scope`.

- [ ] **Step 3: Write the implementation**

This requires `RGADocument` to expose its next Lamport value and a way to mint ids. The Lamport getter already exists (`lamport`). Add a small helper to `RGADocument` for the ordered ids (already added as `orderedVisibleElements()`), then implement the editor:

```swift
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
```

> Inserts are applied inside the loop (so `document.lamport` advances and the next minted id is strictly greater, keeping the chain ordered). Deletes are applied at the end. The returned `ops` array preserves generation order for the caller to enqueue.

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command. Expected: all `RGAEditorTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add morethantasks/CRDT/RGAEditor.swift morethantasksTests/RGAEditorTests.swift
git commit -m "feat(crdt): RGAEditor translates text diffs into ops"
```

---

## Task 10: RGAEditor fuzz test — diffs always reproduce the target

**Files:**
- Modify: `morethantasksTests/RGAEditorTests.swift` (add test)

- [ ] **Step 1: Write the test**

Add to `RGAEditorTests`:
```swift
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
```

- [ ] **Step 2: Run the test**

Run:
```bash
cd /Users/toprakbirben/projects/mtt/morethantasks
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/RGAEditorTests/fuzzDiffReproducesTarget 2>&1 | tail -25
```
Expected: PASS. **If it fails**, the prefix/suffix diff has an edge case (often when old and new share repeated chars). Debug with superpowers:systematic-debugging; the printed failing `(current, next)` pair from the assertion reproduces it.

- [ ] **Step 3: Fix any edge cases found**

If failing, the usual culprit is the suffix scan overrunning the prefix; the `prefixCap - prefix` bound in `applyLocalChange` prevents prefix/suffix overlap. Ensure that bound is present.

- [ ] **Step 4: Confirm green**

Re-run Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add morethantasksTests/RGAEditorTests.swift
git commit -m "test(crdt): fuzz diff→ops reproduces target text"
```

---

## Task 11: Two-replica integration — edit, exchange, converge

**Files:**
- Modify: `morethantasksTests/RGAConvergenceTests.swift` (add test)

- [ ] **Step 1: Write the test**

Add to `RGAConvergenceTests`:
```swift
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
```

- [ ] **Step 2: Run the test**

Run:
```bash
cd /Users/toprakbirben/projects/mtt/morethantasks
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:morethantasksTests/RGAConvergenceTests/twoReplicasConvergeAfterExchange 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 3: Fix if needed**

If red, use superpowers:systematic-debugging — most likely a lamport/clock issue causing an id collision across the two editors (each has a distinct siteId, so collisions should be impossible; verify siteIds differ).

- [ ] **Step 4: Full suite green**

Run the entire CRDT test set:
```bash
xcodebuild test -scheme morethantasks -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:morethantasksTests/CharIDTests \
  -only-testing:morethantasksTests/RGADocumentTests \
  -only-testing:morethantasksTests/RGAConvergenceTests \
  -only-testing:morethantasksTests/RGAEditorTests 2>&1 | tail -30
```
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add morethantasksTests/RGAConvergenceTests.swift
git commit -m "test(crdt): two replicas converge after offline edit exchange"
```

---

## Phase 1 done — definition of success

- [ ] All four test suites pass (`CharIDTests`, `RGADocumentTests`, `RGAConvergenceTests`, `RGAEditorTests`).
- [ ] `RGADocument` and `RGAEditor` have zero dependencies on networking, SQLite, or SwiftUI.
- [ ] Convergence holds under 200+ random orderings, with deletes, and across two replicas.

**Next phase (separate plan, written after this lands):** Phase 2 — wire `RGAEditor` into `NoteView`'s `TextEditor`, persist ops/cursor in SQLite, and expose ops for the sync channel. That plan will reference the concrete types built here (`RGADocument`, `RGAEditor`, `RGAOp`, `CharID`).
```
