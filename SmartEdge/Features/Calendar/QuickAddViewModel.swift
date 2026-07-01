import Foundation
import Combine

/// Parses a single natural-language line ("팀 회의 내일 오후 3시") into an event —
/// title + start + duration — via `NSDataDetector`, and creates it in the user's
/// calendar. There is no public EventKit natural-language parser, so we lean on
/// the system data detector and surface a live preview so the user can confirm.
@MainActor
final class QuickAddViewModel: ObservableObject {
    @Published var text: String = ""
    @Published private(set) var isSaving = false

    /// Set by the presenting window so the view can dismiss after save / cancel.
    var dismiss: (() -> Void)?

    private let calendarService: any CalendarServiceProtocol
    private let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    init(calendarService: any CalendarServiceProtocol) {
        self.calendarService = calendarService
    }

    struct Parsed: Equatable {
        let title: String
        let start: Date
        let duration: TimeInterval
        /// False when no date was detected (we defaulted to "start now").
        let dateDetected: Bool
    }

    /// Live interpretation of the current text; `nil` while empty.
    var parsed: Parsed? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let match = detector?.matches(in: trimmed, options: [], range: range).first,
           let date = match.date {
            var title = trimmed
            if let matchRange = Range(match.range, in: trimmed) {
                title.removeSubrange(matchRange)
            }
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = match.duration > 0 ? match.duration : 3600
            return Parsed(
                title: title.isEmpty ? "New Event" : title,
                start: date,
                duration: duration,
                dateDetected: true
            )
        }

        // No date recognized — default to starting now for an hour.
        return Parsed(title: trimmed, start: Date(), duration: 3600, dateDetected: false)
    }

    func save() async -> Bool {
        guard let parsed else { return false }
        isSaving = true
        defer { isSaving = false }
        return await calendarService.createQuickEvent(
            title: parsed.title,
            startDate: parsed.start,
            duration: parsed.duration
        )
    }
}
