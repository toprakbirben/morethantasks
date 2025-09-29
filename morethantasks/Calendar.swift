//
//  Calendar.swift
//  morethantasks
//
//  Created by Toprak Birben on 06/05/2025.
//
import SwiftUI

struct CalendarPage: View {
    @Binding var selectedTab: UIComponents.Tab
    @State private var notes: [Notes] = []
    @State private var events: [Event] = []
    
    var body: some View {
        HStack {
            CalendarView(events: events)
        }
        .onAppear {
            DatabaseManager.shared.fetchNotes()
            notes = DatabaseManager.shared.getNotes()
            EventManager.shared.createEvents(notes: notes)
            events = EventManager.shared.getEvents()
        }
    }
}

// MARK: - CalendarView

struct CalendarView: View {
    @State private var selectedDate: Date = Date()
    let events: [Event]
    
    // Group events by start-of-day
    private var groupedEvents: [Date: [Event]] {
        Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.startDate) }
    }
    
    var body: some View {
        VStack {
            MonthHeaderView(selectedDate: selectedDate)
            WeekdayHeaderView()
            
            DaysGridView(selectedDate: $selectedDate, events: groupedEvents)
            
            Divider().padding(.vertical, 4)
            
            EventListView(selectedDate: selectedDate, events: groupedEvents)
        }
    }
}

// MARK: - Subviews

struct MonthHeaderView: View {
    var selectedDate: Date
    
    var body: some View {
        Text(Helper.shared.monthYearString(for: selectedDate))
            .font(.title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
}

struct WeekdayHeaderView: View {
    var body: some View {
        HStack {
            ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { day in
                Text(day)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct DaysGridView: View {
    @Binding var selectedDate: Date
    let events: [Date: [Event]]
    
    var body: some View {
        let days = Helper.shared.generateDays(for: selectedDate)
        
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
            ForEach(days, id: \.self) { date in
                if let date = date {
                    VStack(spacing: 4) {
                        Text("\(Calendar.current.component(.day, from: date))")
                            .frame(width: 28, height: 28)
                            .background(Helper.shared.isSameDay(date, selectedDate) ? Color.green : Color.clear)
                            .clipShape(Circle())
                            .foregroundColor(Helper.shared.isSameDay(date, selectedDate) ? .white : .black)
                            .onTapGesture {
                                selectedDate = date
                            }
                        
                        // Event indicator
                        if let dayEvents = events[Calendar.current.startOfDay(for: date)], !dayEvents.isEmpty {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 6, height: 6)
                        } else {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
    }
}

struct EventListView: View {
    let selectedDate: Date
    let events: [Date: [Event]]
    
    var body: some View {
        ScrollView {
            if let todaysEvents = events[Calendar.current.startOfDay(for: selectedDate)] {
                VStack(spacing: 12) {
                    ForEach(todaysEvents) { event in
                        RoundedRectangle(cornerRadius: 12)
                            .frame(height: 60)
                            .background(Color(hex: event.colorHex ?? "#007BFF")?.opacity(0.8) ?? Color.blue.opacity(0.8))
                            .overlay(
                                VStack(alignment: .leading) {
                                    Text(event.title)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text(event.allDay ? "All day" : "Time TBD")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(.leading, 8)
                                
                            )
                    }
                }
                .padding(.horizontal)
            } else {
                Text("No events today")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
    }
}

// MARK: - Preview

struct Calendar_Previews: PreviewProvider {
    static var previews: some View {
        CalendarPage(selectedTab: .constant(.calendar))
    }
}

