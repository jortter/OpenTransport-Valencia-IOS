import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal equivalent of the `HttpURLConnection` helpers in EmtRepository.kt.
enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Returns the body as UTF-8 text whatever the status code (Android reads
    /// the error stream too).
    static func get(_ url: URL, headers: [String: String] = [:]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, _) = try await session.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }

    static func post(_ url: URL, body: Data, headers: [String: String] = [:]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, _) = try await session.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Regex helpers (NSRegularExpression so the package also builds on Linux)

extension String {
    /// Capture groups of every match of `pattern`.
    func matches(of pattern: String, options: NSRegularExpression.Options = []) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = self as NSString
        return regex.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { i in
                let range = match.range(at: i)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
        }
    }

    func firstMatch(of pattern: String, options: NSRegularExpression.Options = []) -> [String]? {
        matches(of: pattern, options: options).first
    }

    func replacingRegex(_ pattern: String, with template: String) -> String {
        replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    /// Strips tags and collapses whitespace.
    var htmlText: String {
        replacingRegex("<[^>]+>", with: " ").replacingRegex(#"\s+"#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
