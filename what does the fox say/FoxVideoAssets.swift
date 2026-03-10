import Foundation

enum VideoAsset: String, CaseIterable {
    case foxidle
    case foxspeaking
    case lovebunny
    case scareoffduolingo
    case toptap
    case midtap
    case bottomtap
}

enum VideoResolver {
    static func url(for name: String) -> URL {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: name, withExtension: "mp4") {
            return url
        }
        if let fallback = bundle.url(forResource: VideoAsset.foxidle.rawValue, withExtension: "mp4") {
            return fallback
        }
        return URL(fileURLWithPath: "/dev/null")
    }
}

extension VideoAsset {
    var url: URL {
        VideoResolver.url(for: rawValue)
    }
}
