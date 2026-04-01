import Foundation

enum ActivityLabel: String, CaseIterable, Codable, Identifiable {
    case diaperWet
    case diaperBowel
    case feeding
    case sleepStart
    case wakeUp
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .diaperWet: return "Diaper (Wet)"
        case .diaperBowel: return "Diaper (Bowel)"
        case .feeding: return "Feeding"
        case .sleepStart: return "Baby Asleep"
        case .wakeUp: return "Baby Wakes Up"
        case .other: return "Other"
        }
    }
}

enum DiaperChangeValue: String, CaseIterable, Codable, Identifiable {
    case wet
    case bm
    case dry

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wet: return "Wet"
        case .bm: return "BM"
        case .dry: return "Dry"
        }
    }
}

enum CaptureType: String, Codable {
    case photo
    case shortVideo
    case audioSnippet
}

struct CaptureEnvelope: Sendable {
    let id: UUID
    let captureType: CaptureType
    let capturedAt: Date
    let deviceId: String?
    let localMediaURL: URL
    let metadata: [String: String]
}

struct InferenceResult: Sendable {
    let label: ActivityLabel
    let confidence: Double
    let rationaleShort: String
    let modelVersion: String
    let feedingAmountOz: Double?
    let mentionedEventTime: MentionedEventTime?
}

struct MentionedEventTime: Sendable {
    let hour: Int
    let minute: Int

    init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }
        self.hour = hour
        self.minute = minute
    }

    func resolvedDate(relativeTo recordingDate: Date, calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: recordingDate)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard var candidate = calendar.date(from: components) else {
            return nil
        }

        // A spoken clock time refers to when the event already happened, so use
        // the most recent occurrence of that time if the same-day value would be future-dated.
        if candidate > recordingDate {
            candidate = calendar.date(byAdding: .day, value: -1, to: candidate) ?? candidate
        }

        return candidate
    }
}
