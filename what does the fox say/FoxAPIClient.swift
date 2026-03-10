import Foundation
import UIKit

final class FoxAPIClient {
    static let shared = FoxAPIClient()

    private let tokenService = "fox.auth"
    private let tokenAccount = "authToken"
    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private init() {}

    enum APIError: Error, LocalizedError {
        case invalidResponse
        case httpStatus(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The server returned an invalid response."
            case .httpStatus(let status, let body):
                debugLog("HTTP \(status) body: \(body)")
                switch status {
                case 401:
                    return "Your session expired. Please try again."
                case 404:
                    return "The requested data is unavailable right now."
                case 429:
                    return "Too many requests. Please wait a moment and try again."
                case 500...599:
                    return "The server is having trouble right now. Please try again later."
                default:
                    return "The server rejected this request."
                }
            }
        }
    }

    struct AuthResponse: Decodable {
        let userId: String
        let token: String
        let deviceId: String
        let expiresIn: Int?
    }

    struct DeviceResponse: Decodable {
        let deviceId: String
    }

    struct UserProfileResponse: Decodable {
        let nativeLanguage: PracticeLanguage
        let targetLanguage: PracticeLanguage
        let persona: String
    }

    struct PracticeSessionsResponse: Decodable {
        let items: [PracticeSessionSummary]
    }

    struct SyncStatusResponse: Decodable {
        let hasUnread: Bool
        let unreadCount: Int
        let processingCount: Int
        let latestUpdatedAt: Date?
    }

    struct MessageResponse: Decodable {
        let ok: Bool?
    }

    var baseURL: URL { FoxAPIConfig.baseURL }

    var hasConfiguredBaseURL: Bool { FoxAPIConfig.hasConfiguredBaseURL }

    func currentToken() -> String? {
        loadToken()
    }

    func authenticateAnonymous(deviceId: String) async throws -> AuthResponse {
        struct Payload: Encodable {
            let deviceId: String
            let deviceModel: String
            let os: String
            let language: String
            let timezone: String

            enum CodingKeys: String, CodingKey {
                case deviceId = "device_id"
                case deviceModel = "device_model"
                case os
                case language
                case timezone
            }
        }

        let payload = Payload(
            deviceId: deviceId,
            deviceModel: UIDevice.current.model,
            os: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            language: Locale.preferredLanguages.first ?? Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )

        let response: AuthResponse = try await request(
            path: "/v1/auth/anonymous",
            method: "POST",
            body: payload,
            requiresAuth: false,
            logSummary: "deviceId=\(foxShortID(deviceId))"
        )
        debugLog(
            .auth,
            "anonymous auth success userId=\(foxShortID(response.userId)) deviceId=\(foxShortID(response.deviceId)) expiresIn=\(response.expiresIn ?? 0)"
        )
        saveToken(response.token)
        return response
    }

    func registerDevice(deviceId: String) async throws -> DeviceResponse {
        struct Payload: Encodable {
            let deviceId: String
            let deviceModel: String
            let os: String
            let language: String
            let timezone: String

            enum CodingKeys: String, CodingKey {
                case deviceId = "device_id"
                case deviceModel = "device_model"
                case os
                case language
                case timezone
            }
        }

        return try await request(
            path: "/v1/devices",
            method: "POST",
            body: Payload(
                deviceId: deviceId,
                deviceModel: UIDevice.current.model,
                os: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                language: Locale.preferredLanguages.first ?? Locale.current.identifier,
                timezone: TimeZone.current.identifier
            ),
            requiresAuth: true,
            logSummary: "deviceId=\(foxShortID(deviceId))"
        )
    }

    func fetchProfile() async throws -> UserProfile {
        let response: UserProfileResponse = try await request(
            path: "/v1/profile",
            method: "GET",
            body: Optional<Int>.none,
            requiresAuth: true,
            logSummary: nil
        )
        debugLog(
            .profile,
            "fetch profile native=\(response.nativeLanguage.rawValue) target=\(response.targetLanguage.rawValue) persona=\(FoxPersona.fromBackend(response.persona).backendName)"
        )
        return UserProfile(
            nativeLanguage: response.nativeLanguage,
            targetLanguage: response.targetLanguage,
            persona: FoxPersona.fromBackend(response.persona)
        )
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        struct Payload: Encodable {
            let nativeLanguage: PracticeLanguage
            let targetLanguage: PracticeLanguage
            let persona: String
        }

        let response: UserProfileResponse = try await request(
            path: "/v1/profile",
            method: "PATCH",
            body: Payload(
                nativeLanguage: profile.nativeLanguage,
                targetLanguage: profile.targetLanguage,
                persona: profile.persona.prompt
            ),
            requiresAuth: true,
            logSummary: "native=\(profile.nativeLanguage.rawValue) target=\(profile.targetLanguage.rawValue) persona=\(profile.persona.backendName)"
        )
        debugLog(
            .profile,
            "update profile success native=\(response.nativeLanguage.rawValue) target=\(response.targetLanguage.rawValue) persona=\(FoxPersona.fromBackend(response.persona).backendName)"
        )
        return UserProfile(
            nativeLanguage: response.nativeLanguage,
            targetLanguage: response.targetLanguage,
            persona: FoxPersona.fromBackend(response.persona)
        )
    }

    func createPracticeSession(profile: UserProfile, deviceId: String) async throws -> PracticeSessionCreateResponse {
        struct Payload: Encodable {
            let deviceId: String
            let nativeLanguage: PracticeLanguage
            let targetLanguage: PracticeLanguage
            let persona: String
        }

        return try await request(
            path: "/v1/practice-sessions",
            method: "POST",
            body: Payload(
                deviceId: deviceId,
                nativeLanguage: profile.nativeLanguage,
                targetLanguage: profile.targetLanguage,
                persona: profile.persona.prompt
            ),
            requiresAuth: true,
            logSummary: "deviceId=\(foxShortID(deviceId)) native=\(profile.nativeLanguage.rawValue) target=\(profile.targetLanguage.rawValue) persona=\(profile.persona.backendName)"
        )
    }

    func uploadSessionAudio(sessionId: String, fileURL: URL, durationSec: Int) async throws -> String? {
        let boundary = "Boundary-\(UUID().uuidString)"
        let fileData = try Data(contentsOf: fileURL)
        let url = makeURL(path: "/v1/practice-sessions/\(sessionId)/audio")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"duration_sec\"\r\n\r\n")
        body.append("\(durationSec)\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: audio/m4a\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpStatus(http.statusCode, text)
        }
        guard !data.isEmpty else {
            return nil
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let audioURL = json["audioURL"] as? String, !audioURL.isEmpty {
                return audioURL
            }
            if let audioURL = json["audioUrl"] as? String, !audioURL.isEmpty {
                return audioURL
            }
            if let audioURL = json["url"] as? String, !audioURL.isEmpty {
                return audioURL
            }
        }
        return nil
    }

    func finalizeSession(sessionId: String, transcript: [TranscriptSegment], durationSec: Int?, audioURL: String? = nil) async throws -> PracticeSessionCreateResponse {
        struct Payload: Encodable {
            let transcriptFullJson: [TranscriptSegment]?
            let durationSec: Int?
            let audioUrl: String?
        }

        let response: PracticeSessionCreateResponse = try await request(
            path: "/v1/practice-sessions/\(sessionId)/finalize",
            method: "PATCH",
            body: Payload(
                transcriptFullJson: transcript.isEmpty ? nil : transcript,
                durationSec: durationSec,
                audioUrl: audioURL
            ),
            requiresAuth: true,
            logSummary: "sessionId=\(foxShortID(sessionId)) transcriptCount=\(transcript.count) durationSec=\(durationSec ?? 0) hasAudioURL=\(audioURL != nil)"
        )
        return response
    }

    func listPracticeSessions() async throws -> [PracticeSessionSummary] {
        let path = "/v1/practice-sessions"
        let url = makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let startedAt = Date()

        if let token = currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        guard 200..<300 ~= http.statusCode else {
            let text = String(data: data, encoding: .utf8) ?? ""
            debugLog(
                .network,
                "GET \(path) status=\(http.statusCode) latency=\(latencyMs)ms body=\(foxPreview(text))"
            )
            throw APIError.httpStatus(http.statusCode, text)
        }

        debugLog(.network, "GET \(path) status=\(http.statusCode) latency=\(latencyMs)ms ")

        let items = try decodePracticeSessionSummaries(from: data)
        let processingSummary = items
            .filter { $0.status == .processing || $0.status == .failed }
            .prefix(3)
            .map {
                "sessionId=\(foxShortID($0.id)) status=\($0.status.rawValue) stage=\($0.processingStage ?? "nil") reason=\(foxPreview($0.failureReason, limit: 80))"
            }
            .joined(separator: " | ")
        let suffix = processingSummary.isEmpty ? "" : " \(processingSummary)"
        debugLog(.history, "list sessions count=\(items.count)\(suffix)")
        return items
    }

    func getPracticeSession(session: PracticeSessionSummary) async throws -> PracticeSessionDetail {
        let path = "/v1/practice-sessions/\(session.id)"
        let url = makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let startedAt = Date()

        if let token = currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        guard 200..<300 ~= http.statusCode else {
            let text = String(data: data, encoding: .utf8) ?? ""
            debugLog(
                .network,
                "GET \(path) status=\(http.statusCode) latency=\(latencyMs)ms sessionId=\(foxShortID(session.id)) body=\(foxPreview(text))"
            )
            throw APIError.httpStatus(http.statusCode, text)
        }

        debugLog(.network, "GET \(path) status=\(http.statusCode) latency=\(latencyMs)ms sessionId=\(foxShortID(session.id))")

        let decoder = makeDecoder()

        do {
            let detail = try decoder.decode(PracticeSessionDetail.self, from: data)
            debugLog(
                .history,
                "detail success sessionId=\(foxShortID(detail.id)) status=\(detail.status.rawValue) stage=\(detail.processingStage ?? "nil") version=\(detail.resultVersion) reason=\(foxPreview(detail.failureReason, limit: 80)) feedbackChars=\(detail.feedbackOverall.count) summaryChars=\(detail.summary.count) transcriptCount=\(detail.transcript.count) observability=\(detailObservabilitySummary(from: data))"
            )
            return detail
        } catch {
            if let review = try? decoder.decode(SessionReview.self, from: data) {
                let detail = PracticeSessionDetail(summary: session, review: review)
                debugLog(
                    .history,
                    "detail success fallback=session_review_only sessionId=\(foxShortID(detail.id)) status=\(detail.status.rawValue) stage=\(detail.processingStage ?? "nil") version=\(detail.resultVersion) feedbackChars=\(detail.feedbackOverall.count) summaryChars=\(detail.summary.count) transcriptCount=\(detail.transcript.count) observability=\(detailObservabilitySummary(from: data))"
                )
                return detail
            }
            if let review = extractSessionReviewFromFeedbackJSON(data: data, decoder: decoder) {
                let detail = PracticeSessionDetail(summary: session, review: review)
                debugLog(
                    .history,
                    "detail success fallback=feedback_json_only sessionId=\(foxShortID(detail.id)) status=\(detail.status.rawValue) stage=\(detail.processingStage ?? "nil") version=\(detail.resultVersion) feedbackChars=\(detail.feedbackOverall.count) summaryChars=\(detail.summary.count) transcriptCount=\(detail.transcript.count) observability=\(detailObservabilitySummary(from: data))"
                )
                return detail
            }
            let responsePreview = String(data: data, encoding: .utf8) ?? ""
            debugLog(
                .history,
                "detail decode failed sessionId=\(foxShortID(session.id)) error=\(foxDecodingErrorSummary(error)) observability=\(detailObservabilitySummary(from: data)) body=\(foxPreview(responsePreview, limit: 320))"
            )
            throw error
        }
    }

    func markSessionRead(sessionId: String, version: Int) async throws {
        struct Payload: Encodable {
            let version: Int
        }

        let _: MessageResponse = try await request(
            path: "/v1/practice-sessions/\(sessionId)/read",
            method: "POST",
            body: Payload(version: version),
            requiresAuth: true,
            logSummary: "sessionId=\(foxShortID(sessionId)) version=\(version)"
        )
    }

    func retryPracticeSession(sessionId: String) async throws -> PracticeSessionCreateResponse {
        try await request(
            path: "/v1/practice-sessions/\(sessionId)/retry",
            method: "POST",
            body: Optional<Int>.none,
            requiresAuth: true,
            logSummary: "sessionId=\(foxShortID(sessionId))"
        )
    }

    func deletePracticeSession(sessionId: String) async throws {
        try await requestNoContent(
            path: "/v1/practice-sessions/\(sessionId)",
            method: "DELETE",
            body: Optional<Int>.none,
            requiresAuth: true,
            logSummary: "sessionId=\(foxShortID(sessionId))"
        )
    }

    func getHistorySyncStatus() async throws -> HistorySyncStatus {
        let response: SyncStatusResponse = try await request(
            path: "/v1/history/sync-status",
            method: "GET",
            body: Optional<Int>.none,
            requiresAuth: true,
            logSummary: nil
        )
        debugLog(
            .history,
            "sync status unread=\(response.unreadCount) hasUnread=\(response.hasUnread) processing=\(response.processingCount)"
        )
        return HistorySyncStatus(
            hasUnread: response.hasUnread,
            unreadCount: response.unreadCount,
            processingCount: response.processingCount,
            latestUpdatedAt: response.latestUpdatedAt
        )
    }

    func realtimeWebSocketURL(sessionId: String) -> URL? {
        guard let token = currentToken() else { return nil }
        guard var components = URLComponents(url: makeURL(path: FoxAPIConfig.realtimePath), resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "token", value: token)
        ]
        return components.url
    }

    func historyWebSocketURL() -> URL? {
        guard let token = currentToken() else { return nil }
        guard var components = URLComponents(url: makeURL(path: FoxAPIConfig.historyPath), resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    private func request<T: Decodable, B: Encodable>(
        path: String,
        method: String,
        body: B?,
        requiresAuth: Bool,
        logSummary: String?
    ) async throws -> T {
        let url = makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let startedAt = Date()

        if requiresAuth, let token = currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        guard 200..<300 ~= http.statusCode else {
            let text = String(data: data, encoding: .utf8) ?? ""
            debugLog(
                .network,
                "\(method) \(path) status=\(http.statusCode) latency=\(latencyMs)ms \(logSummary ?? "") body=\(foxPreview(text))"
            )
            throw APIError.httpStatus(http.statusCode, text)
        }
        debugLog(.network, "\(method) \(path) status=\(http.statusCode) latency=\(latencyMs)ms \(logSummary ?? "")")
        let decoder = makeDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private func requestNoContent<B: Encodable>(
        path: String,
        method: String,
        body: B?,
        requiresAuth: Bool,
        logSummary: String?
    ) async throws {
        let url = makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let startedAt = Date()

        if requiresAuth, let token = currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        guard 200..<300 ~= http.statusCode else {
            let text = String(data: data, encoding: .utf8) ?? ""
            debugLog(
                .network,
                "\(method) \(path) status=\(http.statusCode) latency=\(latencyMs)ms \(logSummary ?? "") body=\(foxPreview(text))"
            )
            throw APIError.httpStatus(http.statusCode, text)
        }
        debugLog(.network, "\(method) \(path) status=\(http.statusCode) latency=\(latencyMs)ms \(logSummary ?? "")")
    }

    private func makeURL(path: String) -> URL {
        if path.contains("?") {
            return URL(string: baseURL.absoluteString + path) ?? baseURL.appendingPathComponent(path)
        }
        return baseURL.appendingPathComponent(path)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = FoxAPIClient.iso8601FractionalFormatter.date(from: raw) {
                return date
            }
            if let date = FoxAPIClient.iso8601Formatter.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(raw)")
        }
        return decoder
    }

    private func extractSessionReviewFromFeedbackJSON(data: Data, decoder: JSONDecoder) -> SessionReview? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let feedbackObject = object["feedbackJson"],
            JSONSerialization.isValidJSONObject(feedbackObject),
            let feedbackData = try? JSONSerialization.data(withJSONObject: feedbackObject)
        else {
            return nil
        }
        return try? decoder.decode(SessionReview.self, from: feedbackData)
    }

    private func detailObservabilitySummary(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "invalid_json"
        }
        let hasFeedbackJson = object["feedbackJson"] != nil
        let feedbackObject = object["feedbackJson"] as? [String: Any]
        let hasFeedbackOverall = (feedbackObject?["feedback_overall"] as? String).map { !$0.isEmpty } ?? false
        let feedbackChars = (feedbackObject?["feedback_overall"] as? String)?.count ?? 0
        let summaryChars = (feedbackObject?["summary"] as? String)?.count ?? 0
        let transcriptCount = (feedbackObject?["transcript"] as? [[String: Any]])?.count
            ?? ((object["transcriptFullJson"] as? [[String: Any]])?.count ?? 0)
        return "hasFeedbackJson=\(hasFeedbackJson) hasFeedbackOverall=\(hasFeedbackOverall) feedbackChars=\(feedbackChars) summaryChars=\(summaryChars) transcriptCount=\(transcriptCount)"
    }

    private func decodePracticeSessionSummaries(from data: Data) throws -> [PracticeSessionSummary] {
        let decoder = makeDecoder()

        if let wrapped = try? decoder.decode(PracticeSessionsResponse.self, from: data) {
            return wrapped.items
        }
        if let direct = try? decoder.decode([PracticeSessionSummary].self, from: data) {
            return direct
        }

        let object = try JSONSerialization.jsonObject(with: data)
        let rawItems: [Any]
        if let dictionary = object as? [String: Any], let items = dictionary["items"] as? [Any] {
            rawItems = items
        } else if let items = object as? [Any] {
            rawItems = items
        } else {
            let text = String(data: data, encoding: .utf8) ?? ""
            debugLog(.history, "list decode failed body=\(foxPreview(text, limit: 320))")
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unsupported practice sessions response shape")
            )
        }

        var decoded: [PracticeSessionSummary] = []
        for (index, item) in rawItems.enumerated() {
            guard JSONSerialization.isValidJSONObject(item) else { continue }
            let itemData = try JSONSerialization.data(withJSONObject: item)
            do {
                let summary = try decoder.decode(PracticeSessionSummary.self, from: itemData)
                decoded.append(summary)
            } catch {
                let preview = String(data: itemData, encoding: .utf8) ?? ""
                debugLog(.history, "list item decode failed index=\(index) body=\(foxPreview(preview, limit: 220))")
            }
        }

        if decoded.isEmpty {
            let text = String(data: data, encoding: .utf8) ?? ""
            debugLog(.history, "list decode failed no_valid_items body=\(foxPreview(text, limit: 320))")
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "No valid practice session items found")
            )
        }

        return decoded
    }

    private func saveToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        KeychainHelper.save(data, service: tokenService, account: tokenAccount)
    }

    private func loadToken() -> String? {
        guard let data = KeychainHelper.read(service: tokenService, account: tokenAccount) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
