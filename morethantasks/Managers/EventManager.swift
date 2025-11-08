//
//  EventManager.swift
//  morethantasks
//
//  Created by Toprak Birben on 29/09/2025.
//
import Foundation

struct Event: Identifiable, Codable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var location: String?
    var allDay: Bool
    var colorHex: String? /*{
        DatabaseManager.shared.notesArray.first(where: { $0.id == id })?.colorHex
                           } */ = "#FFFFFF"
    
    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        allDay: Bool = false,
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.allDay = allDay
    }
}

@MainActor
class EventManager : ObservableObject
{
    @Published var eventList : [Event] = []
    static let shared = EventManager()

    func parseEvent(note: Notes) -> Event? {
        let text = note.body
        let pattern = #"@(\d{2})-(\d{2})-(\d{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }

        let day = Int((text as NSString).substring(with: match.range(at: 1))) ?? 1
        let month = Int((text as NSString).substring(with: match.range(at: 2))) ?? 1
        let year = Int((text as NSString).substring(with: match.range(at: 3))) ?? 2000
        
        var dateComponents = DateComponents()
        dateComponents.day = day
        dateComponents.month = month
        dateComponents.year = year
        
        guard let date = Calendar.current.date(from: dateComponents) else { return nil }
        
        let cleanedTitle = Helper.shared.extractTitle(from: text)
        
        let startDate = Calendar.current.startOfDay(for: date)
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        
        
        return Event(
            id: note.id,
            title: cleanedTitle.isEmpty ? "Untitled Event" : cleanedTitle,
            startDate: startDate,
            endDate: endDate,
            allDay: true,
        )
    }
    
    func createEvents(notes: [Notes]) {
        for note in notes {
            if eventList.contains(where: { $0.id == note.id }) {continue}
            guard let event = parseEvent(note: note) else { continue }
            eventList.append(event)
        }
    }
    
    func getEvents() -> [Event] {
        return eventList
    }
    
}


