import Foundation

/// Credential hygiene. The publishable key, client token, and full checkout URL
/// (carries `#t=<token>`) must NEVER reach a log. The only safe rule on iOS is to
/// never pass a secret to a logging API at all — even `os_log` `%{private}` is
/// unmasked on an attached device. Debug logging is off by default and still
/// redacts.
enum Redact {

    /// Reduce a URL string to `scheme://host[:port]/path`, dropping query + fragment.
    static func redactURL(_ string: String) -> String {
        guard let c = URLComponents(string: string), let scheme = c.scheme, let host = c.host else {
            return "[unparseable-url]"
        }
        let port = c.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)\(c.path)"
    }

    /// Scrub key-shaped and token substrings from arbitrary text.
    static func redactSecrets(_ input: String) -> String {
        var out = input
        // Case‑insensitive on the `pk_/gk_` prefix and the `Bearer` literal to
        // match the RN SDK's `/gi` (a `PK_LIVE_…` or `BEARER …` must still scrub).
        out = replace(out, pattern: "([gp]k_(live|test)_)[0-9a-fA-F]{6,}", template: "$1redacted", options: [.caseInsensitive])
        out = replace(out, pattern: "([#?&]t=)[^\\s&\"']+", template: "$1redacted")
        out = replace(out, pattern: "(Bearer\\s+)[^\\s\"']+", template: "$1redacted", options: [.caseInsensitive])
        return out
    }

    private static func replace(_ input: String, pattern: String, template: String,
                                options: NSRegularExpression.Options = []) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return re.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }

    // The debug flag is written from the config actor and read from the main
    // thread, so guard it with a lock to stay data-race free.
    private static let debugLock = NSLock()
    private static var debugEnabled = false

    static func setDebug(_ on: Bool) {
        debugLock.lock(); defer { debugLock.unlock() }
        debugEnabled = on
    }

    private static func isDebug() -> Bool {
        debugLock.lock(); defer { debugLock.unlock() }
        return debugEnabled
    }

    /// Debug logger. Off by default; even when on it redacts every line. Uses
    /// `print` (compiled out of release logging pipelines) — never `os_log`.
    static func log(_ parts: String...) {
        guard isDebug() else { return }
        print("[GbitXPay]", redactSecrets(parts.joined(separator: " ")))
    }
}
