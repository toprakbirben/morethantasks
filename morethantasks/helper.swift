//
//  helper.swift
//  morethantasks
//
//  Created by Toprak Birben on 09/09/2025.
//

import SwiftUI

extension Color {
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }
        
        guard hexString.count == 6,
              let rgb = UInt64(hexString, radix: 16) else {
            return nil
        }
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255
        let green = Double((rgb & 0x00FF00) >> 8) / 255
        let blue = Double(rgb & 0x0000FF) / 255
        
        self.init(red: red, green: green, blue: blue)
    }
}

