import Foundation

enum FoxAPIConfig {
    static var baseURL: URL {
        if let fromEnv = normalizedURLString(ProcessInfo.processInfo.environment["FOX_BACKEND_BASE_URL"]),
           let url = URL(string: fromEnv) {
            return url
        }
        if let fromPlist = normalizedURLString(Bundle.main.object(forInfoDictionaryKey: "FOXBackendBaseURL") as? String),
           let url = URL(string: fromPlist) {
            return url
        }
        return URL(string: "https://example.com")!
    }

    static var realtimePath: String {
        stringValue(infoKey: "FOXRealtimeWSPath", envKey: "FOX_REALTIME_WS_PATH") ?? "/v1/realtime/ws"
    }

    static var historyPath: String {
        stringValue(infoKey: "FOXHistoryWSPath", envKey: "FOX_HISTORY_WS_PATH") ?? "/v1/history/ws"
    }

    static var hasConfiguredBaseURL: Bool {
        baseURL.host != "example.com"
    }

    private static func stringValue(infoKey: String, envKey: String) -> String? {
        if let fromEnv = ProcessInfo.processInfo.environment[envKey], !fromEnv.isEmpty {
            return fromEnv
        }
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
           !fromPlist.isEmpty {
            return fromPlist
        }
        return nil
    }

    private static func normalizedURLString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }
}
