//
//  helper.swift
//  morethantasks
//
//  Created by Toprak Birben on 09/09/2025.
//

import SwiftUI
import Foundation
import UIKit
import EventKit
import Combine
import NaturalLanguage


extension Color {
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }
        
        if hexString.count != 6 || UInt64(hexString, radix: 16) == nil {
            self = .blue
            return
        }
        
        let rgb = UInt64(hexString, radix: 16)!
        let red   = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue  = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
}

    
class Helper {
    
    static let shared = Helper()
        
    private init() {}

    static let dateMarkerPattern = #"/date (\d{2}-\d{2}-\d{4})(?: (\d{2}:\d{2}))?"#

    func extractTitle(from text: String) -> String {
        let contextText = text.replacingOccurrences(of: Helper.dateMarkerPattern, with: "", options: .regularExpression)

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = contextText

        var keywords: [String] = []

        tagger.enumerateTags(in: contextText.startIndex..<contextText.endIndex,
                             unit: .word,
                             scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, tokenRange in
            if let tag = tag, tag == .noun || tag == .verb {
                let word = String(contextText[tokenRange])
                keywords.append(word)
            }
            return true
        }

        return keywords.joined(separator: " ")
    }

    struct DateMarkerMatch {
        let range: Range<String.Index>
        let date: Date
        let hasTime: Bool
    }

    /// Locates a `/date DD-MM-YYYY` or `/date DD-MM-YYYY HH:mm` marker in note text,
    /// including the range of the raw command text so callers can splice it out.
    func findDateMarker(in text: String) -> DateMarkerMatch? {
        let regex = try! NSRegularExpression(pattern: Helper.dateMarkerPattern)

        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let fullRange = Range(match.range, in: text),
              let dateRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let dateString = String(text[dateRange])
        let timeRange = Range(match.range(at: 2), in: text)
        let hasTime = timeRange != nil

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = hasTime ? "dd-MM-yyyy HH:mm" : "dd-MM-yyyy"

        let fullString = hasTime ? "\(dateString) \(String(text[timeRange!]))" : dateString
        guard let date = dateFormatter.date(from: fullString) else { return nil }

        return DateMarkerMatch(range: fullRange, date: date, hasTime: hasTime)
    }

    /// Parses a `/date DD-MM-YYYY` or `/date DD-MM-YYYY HH:mm` marker from note text.
    /// `hasTime` is false when no time was given, meaning the caller should treat it as all-day.
    func parseDateMarker(from text: String) -> (date: Date, hasTime: Bool)? {
        guard let match = findDateMarker(in: text) else { return nil }
        return (match.date, match.hasTime)
    }

    /// The collapsed, human-readable form shown once a /date marker is finished: "28/07/2026" or "28/07/2026 14:30".
    func prettyDateMarkerText(date: Date, hasTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = hasTime ? "dd/MM/yyyy HH:mm" : "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    /// Reconstructs the raw, editable "/date DD-MM-YYYY[ HH:mm]" command from a previously parsed date.
    func rawDateMarkerText(date: Date, hasTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = hasTime ? "dd-MM-yyyy HH:mm" : "dd-MM-yyyy"
        return "/date " + formatter.string(from: date)
    }

    func filteredNotes(searchText: String, notes : [Notes]) -> [Notes] {
        if searchText.isEmpty {
            return notes
        } else {
            return notes.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText) ||
                note.body.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    func monthYearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }
        
    func isSameDay(_ d1: Date, _ d2: Date) -> Bool {
        Calendar.current.isDate(d1, inSameDayAs: d2)
    }
        
    func generateDays(for date: Date) -> [Date?] {
        var days: [Date?] = []
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        
        let startOfMonth = monthInterval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)!.count
        let firstWeekday = calendar.component(.weekday, from: startOfMonth) - 2
        let offset = firstWeekday < 0 ? 6 : firstWeekday
        
        for _ in 0..<offset { days.append(nil) }
        for day in 1...daysInMonth {
            if let dayDate = calendar.date(byAdding: .day, value: day-1, to: startOfMonth) {
                days.append(dayDate)
            }
        }
        return days
    }
}
    

