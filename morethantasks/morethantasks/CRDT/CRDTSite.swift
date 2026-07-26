//  CRDTSite.swift
//  Stable per-installation identity for the local RGA CRDT engine. NOT synced
//  across devices — the same user on two devices is deliberately two sites
//  (see docs/superpowers/specs/2026-06-02-collaborative-editing-design.md,
//  Section 2 "Identity").
import Foundation

enum CRDTSite {
    private static let key = "crdtSiteId"

    static func id(using defaults: UserDefaults = .standard) -> UUID {
        if let stored = defaults.string(forKey: key), let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let fresh = UUID()
        defaults.set(fresh.uuidString, forKey: key)
        return fresh
    }
}
