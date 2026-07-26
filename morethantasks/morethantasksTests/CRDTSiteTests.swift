//  CRDTSiteTests.swift
import Testing
import Foundation
@testable import morethantasks

struct CRDTSiteTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "CRDTSiteTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test func generatesAndPersistsAnIdOnFirstCall() {
        let defaults = freshDefaults()
        let first = CRDTSite.id(using: defaults)
        let second = CRDTSite.id(using: defaults)
        #expect(first == second)
    }

    @Test func differentDefaultsSuitesGetDifferentIds() {
        let a = CRDTSite.id(using: freshDefaults())
        let b = CRDTSite.id(using: freshDefaults())
        #expect(a != b)
    }
}
