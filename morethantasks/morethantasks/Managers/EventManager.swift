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
    @MainActor
        var colorHex: String? {
            DatabaseManager.shared.notesArray.first(where: { $0.id == id })?.colorHex
        }
    
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
        guard let parsed = Helper.shared.parseDateMarker(from: text) else { return nil }

        let cleanedTitle = Helper.shared.extractTitle(from: text)
        let fallbackTitle = note.title.isEmpty ? "Untitled Event" : note.title

        let startDate = parsed.hasTime ? parsed.date : Calendar.current.startOfDay(for: parsed.date)
        let endDate = Calendar.current.date(byAdding: parsed.hasTime ? .hour : .day, value: 1, to: startDate)!

        return Event(
            id: note.id,
            title: cleanedTitle.isEmpty ? fallbackTitle : cleanedTitle,
            startDate: startDate,
            endDate: endDate,
            allDay: !parsed.hasTime,
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


