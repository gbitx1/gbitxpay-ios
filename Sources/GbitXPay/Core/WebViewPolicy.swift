import Foundation

/// Pure, unit-testable origin decisions — the trust the SDK rests on. No WebKit
/// import so it can be tested without a WebView and audited in isolation.
///
/// EXACT origin equality everywhere (scheme + host + port). WKWebView has no
/// `originWhitelist` prop, so the navigation-delegate gate below is the sole
/// authority — and it must never use `hasPrefix`/`contains` (that would allow
/// `pay.gbitx.com.evil.com`).
enum WebViewPolicy {

    /// Canonical `scheme://host[:port]` origin, omitting default ports. Lowercased.
    static func canonicalOrigin(scheme: String?, host: String?, port: Int?) -> String? {
        guard let scheme = scheme?.lowercased(), !scheme.isEmpty,
              let host = host?.lowercased(), !host.isEmpty else { return nil }
        if let port = port {
            let isDefault = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
            return isDefault ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    static func canonicalOrigin(_ url: URL) -> String? {
        canonicalOrigin(scheme: url.scheme, host: url.host, port: url.port)
    }

    /// May a navigation load inside the WebView? Only the exact pinned origin over
    /// https. Everything else is blocked and opened nowhere.
    static func mayLoadInWebView(checkoutOrigin: String, url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return canonicalOrigin(url) == checkoutOrigin
    }

    /// May a bridge message be trusted? Stricter: exact origin AND a `/p/` path.
    /// `WKSecurityOrigin` exposes no path, so callers pass the committed main-frame
    /// URL here (see the message bridge).
    static func isTrustedMessageSource(checkoutOrigin: String, url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              canonicalOrigin(url) == checkoutOrigin else { return false }
        return url.path.hasPrefix("/p/")
    }
}
