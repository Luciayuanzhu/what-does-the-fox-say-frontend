import Foundation

enum PracticeLanguage: String, CaseIterable, Codable, Identifiable {
    case arabic = "Arabic"
    case bengali = "Bengali"
    case bulgarian = "Bulgarian"
    case chineseSimplified = "Chinese (Simplified)"
    case chineseTraditional = "Chinese (Traditional)"
    case croatian = "Croatian"
    case czech = "Czech"
    case danish = "Danish"
    case dutch = "Dutch"
    case english = "English"
    case estonian = "Estonian"
    case finnish = "Finnish"
    case french = "French"
    case german = "German"
    case greek = "Greek"
    case hebrew = "Hebrew"
    case hindi = "Hindi"
    case hungarian = "Hungarian"
    case indonesian = "Indonesian"
    case italian = "Italian"
    case japanese = "Japanese"
    case korean = "Korean"
    case latvian = "Latvian"
    case lithuanian = "Lithuanian"
    case norwegian = "Norwegian"
    case polish = "Polish"
    case portuguese = "Portuguese"
    case romanian = "Romanian"
    case russian = "Russian"
    case serbian = "Serbian"
    case slovak = "Slovak"
    case slovenian = "Slovenian"
    case spanish = "Spanish"
    case swedish = "Swedish"
    case thai = "Thai"
    case turkish = "Turkish"
    case ukrainian = "Ukrainian"
    case vietnamese = "Vietnamese"

    var id: String { rawValue }
}

enum FoxPersona: String, CaseIterable, Codable, Identifiable {
    case sarcastic
    case sweet
    case indifferent
    case impatient

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var backendName: String {
        rawValue
    }

    var summary: String {
        switch self {
        case .sarcastic:
            return "Playful teasing, still helpful."
        case .sweet:
            return "Warm, encouraging, and gentle."
        case .indifferent:
            return "Cool-headed, concise, low-drama."
        case .impatient:
            return "Fast-paced correction with pressure."
        }
    }

    var prompt: String {
        switch self {
        case .sarcastic:
            return "Playfully sharp and teasing, with witty remarks that challenge the user without sounding genuinely mean."
        case .sweet:
            return "Warm, encouraging, and supportive, making the conversation feel kind, patient, and emotionally safe."
        case .indifferent:
            return "Detached and emotionally neutral, responding in a minimal, matter-of-fact way without much enthusiasm or warmth."
        case .impatient:
            return "Brief, slightly irritated, and quick-paced, sounding like they want the user to get to the point and keep up."
        }
    }

    static func fromBackend(_ value: String) -> FoxPersona {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = FoxPersona(rawValue: normalized) {
            return exact
        }
        if let byName = FoxPersona.allCases.first(where: { $0.title.lowercased() == normalized }) {
            return byName
        }
        if let byPrompt = FoxPersona.allCases.first(where: { $0.prompt.lowercased() == normalized }) {
            return byPrompt
        }
        if normalized.contains("sharp") || normalized.contains("teasing") || normalized.contains("witty") {
            return .sarcastic
        }
        if normalized.contains("warm") || normalized.contains("encouraging") || normalized.contains("supportive") {
            return .sweet
        }
        if normalized.contains("detached") || normalized.contains("neutral") || normalized.contains("matter-of-fact") {
            return .indifferent
        }
        if normalized.contains("irritated") || normalized.contains("quick-paced") || normalized.contains("get to the point") {
            return .impatient
        }
        return .sweet
    }
}

struct UserProfile: Codable, Equatable {
    var nativeLanguage: PracticeLanguage
    var targetLanguage: PracticeLanguage
    var persona: FoxPersona

    static let placeholder = UserProfile(
        nativeLanguage: .english,
        targetLanguage: .spanish,
        persona: .sweet
    )
}

enum PracticeSessionStatus: String, Codable {
    case active
    case draft
    case processing
    case ready
    case failed
}

enum TranscriptSpeaker: String, Codable {
    case user
    case assistant
    case fox
}

struct TranscriptSegment: Codable, Identifiable, Hashable {
    let id: String
    let speaker: TranscriptSpeaker
    let text: String

    init(id: String = UUID().uuidString, speaker: TranscriptSpeaker, text: String) {
        self.id = id
        self.speaker = speaker
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case seq
        case speaker
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let seq = try container.decodeIfPresent(Int.self, forKey: .seq)
        let rawSpeaker = try container.decode(String.self, forKey: .speaker)
        self.id = seq.map(String.init) ?? UUID().uuidString
        self.speaker = TranscriptSpeaker(rawValue: rawSpeaker) ?? .assistant
        self.text = try container.decode(String.self, forKey: .text)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(speaker == .fox ? TranscriptSpeaker.assistant.rawValue : speaker.rawValue, forKey: .speaker)
        try container.encode(text, forKey: .text)
    }
}

struct SessionReview: Decodable, Hashable {
    var topicTitle: String
    var summary: String
    var feedbackOverall: String
    var transcript: [TranscriptSegment]

    init(topicTitle: String, summary: String, feedbackOverall: String, transcript: [TranscriptSegment]) {
        self.topicTitle = topicTitle
        self.summary = summary
        self.feedbackOverall = feedbackOverall
        self.transcript = transcript
    }

    static let empty = SessionReview(
        topicTitle: "",
        summary: "",
        feedbackOverall: "",
        transcript: []
    )

    private enum CodingKeys: String, CodingKey {
        case topicTitle
        case summary
        case feedbackOverall
        case transcript
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topicTitle = try container.decodeIfPresent(String.self, forKey: .topicTitle) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        feedbackOverall = try container.decodeIfPresent(String.self, forKey: .feedbackOverall) ?? ""
        transcript = try container.decodeIfPresent([TranscriptSegment].self, forKey: .transcript) ?? []
    }
}

func foxReadableProcessingStage(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
        .replacingOccurrences(of: "_", with: " ")
        .split(separator: " ")
        .map { $0.capitalized }
        .joined(separator: " ")
}

struct PracticeSessionSummary: Decodable, Identifiable, Hashable {
    let id: String
    var title: String
    var summaryText: String
    var nativeLanguage: PracticeLanguage
    var targetLanguage: PracticeLanguage
    var persona: FoxPersona
    var status: PracticeSessionStatus
    var processingStage: String?
    var startedAt: Date
    var updatedAt: Date
    var resultVersion: Int
    var lastReadVersion: Int
    var failureReason: String?

    var isUnread: Bool {
        resultVersion > lastReadVersion
    }

    var languagePairLabel: String {
        "\(nativeLanguage.rawValue) -> \(targetLanguage.rawValue)"
    }

    var processingStageLabel: String? {
        foxReadableProcessingStage(processingStage)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "sessionId"
        case title = "topicTitle"
        case transcriptPreview
        case summary
        case nativeLanguage
        case targetLanguage
        case persona
        case status
        case processingStage
        case startedAt
        case updatedAt
        case resultVersion
        case lastReadVersion
        case isUnread
        case feedback = "feedbackJson"
        case failureReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decodeLanguage(_ key: CodingKeys, fallback: PracticeLanguage = .english) throws -> PracticeLanguage {
            if let value = try container.decodeIfPresent(PracticeLanguage.self, forKey: key) {
                return value
            }
            if let raw = try container.decodeIfPresent(String.self, forKey: key),
               let mapped = PracticeLanguage(rawValue: raw) {
                return mapped
            }
            return fallback
        }
        id = try container.decode(String.self, forKey: .id)
        nativeLanguage = try decodeLanguage(.nativeLanguage)
        targetLanguage = try decodeLanguage(.targetLanguage, fallback: nativeLanguage)
        let personaValue = try container.decodeIfPresent(String.self, forKey: .persona) ?? ""
        persona = FoxPersona.fromBackend(personaValue)
        status = try container.decode(PracticeSessionStatus.self, forKey: .status)
        processingStage = try container.decodeIfPresent(String.self, forKey: .processingStage)
        let decodedStartedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        let decodedUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        startedAt = decodedStartedAt ?? decodedUpdatedAt ?? Date()
        updatedAt = decodedUpdatedAt ?? decodedStartedAt ?? startedAt
        resultVersion = try container.decodeIfPresent(Int.self, forKey: .resultVersion) ?? 0
        lastReadVersion = try container.decodeIfPresent(Int.self, forKey: .lastReadVersion)
            ?? ((try container.decodeIfPresent(Bool.self, forKey: .isUnread)) == true ? 0 : resultVersion)
        let review = try container.decodeIfPresent(SessionReview.self, forKey: .feedback)
        let transcriptPreview = try container.decodeIfPresent(String.self, forKey: .transcriptPreview) ?? ""
        let summaryValue = try container.decodeIfPresent(String.self, forKey: .summary)
            ?? review?.summary
            ?? transcriptPreview
        summaryText = summaryValue
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        let reviewTitle = review?.topicTitle.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackTitleSource = summaryValue.isEmpty ? transcriptPreview : summaryValue
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? (!reviewTitle.isEmpty ? reviewTitle : nil)
            ?? fallbackTitleSource
                .split(separator: ".")
                .first
                .map(String.init)
            ?? "Practice Session"
    }
}

struct PracticeSessionDetail: Decodable, Identifiable, Hashable {
    let id: String
    var title: String
    var nativeLanguage: PracticeLanguage
    var targetLanguage: PracticeLanguage
    var persona: FoxPersona
    var status: PracticeSessionStatus
    var processingStage: String?
    var startedAt: Date
    var updatedAt: Date
    var resultVersion: Int
    var lastReadVersion: Int
    var transcriptPreview: String
    var summary: String
    var transcript: [TranscriptSegment]
    var feedbackOverall: String
    var failureReason: String?

    var isUnread: Bool {
        resultVersion > lastReadVersion
    }

    var processingStageLabel: String? {
        foxReadableProcessingStage(processingStage)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "sessionId"
        case title = "topicTitle"
        case nativeLanguage
        case targetLanguage
        case persona
        case status
        case processingStage
        case startedAt
        case updatedAt
        case resultVersion
        case lastReadVersion
        case transcriptPreview
        case transcript = "transcriptFullJson"
        case feedback = "feedbackJson"
        case failureReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decodeLanguage(_ key: CodingKeys, fallback: PracticeLanguage = .english) throws -> PracticeLanguage {
            if let value = try container.decodeIfPresent(PracticeLanguage.self, forKey: key) {
                return value
            }
            if let raw = try container.decodeIfPresent(String.self, forKey: key),
               let mapped = PracticeLanguage(rawValue: raw) {
                return mapped
            }
            return fallback
        }
        id = try container.decode(String.self, forKey: .id)
        nativeLanguage = try decodeLanguage(.nativeLanguage)
        targetLanguage = try decodeLanguage(.targetLanguage, fallback: nativeLanguage)
        let personaValue = try container.decodeIfPresent(String.self, forKey: .persona) ?? ""
        persona = FoxPersona.fromBackend(personaValue)
        status = try container.decode(PracticeSessionStatus.self, forKey: .status)
        processingStage = try container.decodeIfPresent(String.self, forKey: .processingStage)
        let decodedStartedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        let decodedUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        startedAt = decodedStartedAt ?? decodedUpdatedAt ?? Date()
        updatedAt = decodedUpdatedAt ?? decodedStartedAt ?? startedAt
        resultVersion = try container.decodeIfPresent(Int.self, forKey: .resultVersion) ?? 0
        lastReadVersion = try container.decodeIfPresent(Int.self, forKey: .lastReadVersion) ?? 0
        transcriptPreview = try container.decodeIfPresent(String.self, forKey: .transcriptPreview) ?? ""
        let review = try container.decodeIfPresent(SessionReview.self, forKey: .feedback) ?? .empty
        let rootTranscript = try container.decodeIfPresent([TranscriptSegment].self, forKey: .transcript) ?? []
        summary = review.summary.isEmpty ? transcriptPreview : review.summary
        feedbackOverall = review.feedbackOverall
        transcript = review.transcript.isEmpty ? rootTranscript : review.transcript
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        let reviewTitle = review.topicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitleSource = summary.isEmpty ? transcriptPreview : summary
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? (!reviewTitle.isEmpty ? reviewTitle : nil)
            ?? fallbackTitleSource
                .split(separator: ".")
                .first
                .map(String.init)
            ?? "Practice Session"
    }
}

extension PracticeSessionDetail {
    init(summary session: PracticeSessionSummary, review: SessionReview) {
        id = session.id
        title = review.topicTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? session.title : review.topicTitle
        nativeLanguage = session.nativeLanguage
        targetLanguage = session.targetLanguage
        persona = session.persona
        status = session.status
        processingStage = session.processingStage
        startedAt = session.startedAt
        updatedAt = session.updatedAt
        resultVersion = session.resultVersion
        lastReadVersion = session.lastReadVersion
        transcriptPreview = session.summaryText
        summary = review.summary.isEmpty ? session.summaryText : review.summary
        transcript = review.transcript
        feedbackOverall = review.feedbackOverall
        failureReason = session.failureReason
    }
}

struct HistorySyncStatus: Codable, Equatable {
    var hasUnread: Bool
    var unreadCount: Int
    var processingCount: Int
    var latestUpdatedAt: Date?

    static let empty = HistorySyncStatus(hasUnread: false, unreadCount: 0, processingCount: 0, latestUpdatedAt: nil)
}

struct PracticeSessionCreateResponse: Codable {
    let sessionId: String
    let status: PracticeSessionStatus
    let processingStage: String?
}

struct HistoryPushEvent: Codable {
    let type: String
    let sessionId: String?
    let status: PracticeSessionStatus?
    let processingStage: String?
    let resultVersion: Int?
}

enum FoxStorageKeys {
    static let onboardingCompleted = "fox.onboarding.completed"
    static let localProfile = "fox.profile.local"
    static let reviewMainPageEntryCount = "fox.review.mainPageEntryCount"
    static let reviewPromptShown = "fox.review.promptShown"
    static let initialLaunch = "fox.initialLaunch.raw"
    static let initialLaunchDisplay = "Initial Launch Display"
}
