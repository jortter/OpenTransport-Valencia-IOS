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
        return try await send(request)
    }

    static func post(_ url: URL, body: Data, headers: [String: String] = [:]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await send(request)
    }

    private static func send(_ request: URLRequest) async throws -> String {
        do {
            let (data, response) = try await session.data(for: request)
            let text = String(decoding: data, as: UTF8.self)
            NetworkLog.record(request, status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: text)
            return text
        } catch {
            NetworkLog.record(request, error: error)
            throw error
        }
    }
}

/// The latest request to each endpoint and its outcome, shown in Settings →
/// diagnostics so a failing service can be told from an empty one on a real
/// device. (EMT buses are polled every second, so only the latest is kept.)
public enum NetworkLog {
    public struct Entry: Identifiable, Sendable {
        public var id: String { endpoint }
        public let date: Date
        public let method: String
        /// Host and path only: queries can carry API keys.
        public let endpoint: String
        public let status: Int
        public let bytes: Int
        public let preview: String
        public let error: String?
        public let successes: Int
        public let failures: Int
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var latest: [String: Entry] = [:]

    public static var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return latest.values.sorted { $0.date > $1.date }
    }

    static func record(_ request: URLRequest, status: Int = 0, body: String = "", error: Error? = nil) {
        let url = request.url
        var endpoint = (url?.host ?? "?") + (url?.path ?? "")
        // Collapse ids in paths (stop codes, stations) into one row per service.
        endpoint = endpoint.replacingRegex(#"/\d+(?=/|$)"#, with: "/…")
        let ok = error == nil && (200..<300).contains(status)
        lock.lock()
        defer { lock.unlock() }
        let previous = latest[endpoint]
        latest[endpoint] = Entry(
            date: Date(), method: request.httpMethod ?? "GET", endpoint: endpoint, status: status,
            bytes: body.utf8.count, preview: String(body.prefix(200)),
            error: error.map { ($0 as NSError).localizedDescription },
            successes: (previous?.successes ?? 0) + (ok ? 1 : 0),
            failures: (previous?.failures ?? 0) + (ok ? 0 : 1)
        )
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
