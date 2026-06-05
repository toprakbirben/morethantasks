//
//  ServerConfig.swift
//  morethantasks
//
//  Single source of truth for the backend address. The FastAPI server and the
//  Postgres host both live behind this address; when the dev machine's IP
//  changes (DHCP), update `host` here only.
//

import Foundation

enum ServerConfig {
    // 127.0.0.1 works from the simulator (it shares the Mac's network) and the
    // locally-running API. For a physical device, set this to the Mac's LAN IP.
    static let host = "127.0.0.1"
    static let apiPort = 8000

    static var apiBaseURL: String { "http://\(host):\(apiPort)" }
}
