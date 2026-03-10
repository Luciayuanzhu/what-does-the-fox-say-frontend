import Foundation

enum FoxLogCategory: String {
    case general
    case auth
    case profile
    case session
    case realtime
    case history
    case network
    case audio
    case ui
    case lifecycle
    case error
}

func debugLog(_ category: FoxLogCategory, _ message: @autoclosure () -> String) {
#if DEBUG
    print("[fox][\(category.rawValue)]", message())
#endif
}

func debugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    debugLog(.general, message())
#endif
}

func foxShortID(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "nil" }
    if value.count <= 12 { return value }
    return "\(value.prefix(6))...\(value.suffix(4))"
}

func foxPreview(_ value: String?, limit: Int = 240) -> String {
    guard let value, !value.isEmpty else { return "" }
    let normalized = value.replacingOccurrences(of: "\n", with: " ")
    if normalized.count <= limit {
        return normalized
    }
    return "\(normalized.prefix(limit))..."
}

func foxRedactToken(in value: String?) -> String {
    guard let value, !value.isEmpty else { return "" }
    guard let range = value.range(of: "token=") else { return value }
    let prefix = value[..<range.upperBound]
    return "\(prefix)REDACTED"
}

func foxDecodingErrorSummary(_ error: Error) -> String {
    guard let decodingError = error as? DecodingError else {
        return error.localizedDescription
    }

    func pathString(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else { return "<root>" }
        return path.map { $0.stringValue }.joined(separator: ".")
    }

    switch decodingError {
    case .keyNotFound(let key, let context):
        return "keyNotFound key=\(key.stringValue) path=\(pathString(context.codingPath))"
    case .typeMismatch(let type, let context):
        return "typeMismatch type=\(type) path=\(pathString(context.codingPath))"
    case .valueNotFound(let type, let context):
        return "valueNotFound type=\(type) path=\(pathString(context.codingPath))"
    case .dataCorrupted(let context):
        return "dataCorrupted path=\(pathString(context.codingPath)) desc=\(context.debugDescription)"
    @unknown default:
        return error.localizedDescription
    }
}
