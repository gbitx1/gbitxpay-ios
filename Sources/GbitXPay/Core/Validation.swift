import Foundation

/// Key / argument validation and URL building. Anchored, FULL-string regex
/// matching — a substring match would let a crafted `paymentId` inject
/// `?`/`#`/path segments into the checkout URL (an NSRegularExpression footgun).
enum Validation {

    /// Validate the publishable key BEFORE any network call. A secret key gets a
    /// dedicated error; the key value is never included in a thrown message.
    static func assertPublishableKey(_ raw: String) throws -> (key: String, environment: GbitXPayEnvironment) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GbitXPayError.invalidKey }
        if key.hasPrefix("gk_") { throw GbitXPayError.secretKeyUsed }
        guard fullMatch(key, pattern: "^pk_(live|test)_[0-9a-f]{64}$") else { throw GbitXPayError.invalidKey }
        return (key, key.hasPrefix("pk_live_") ? .live : .test)
    }

    static func assertPaymentArgs(paymentId: String, clientToken: String) throws -> (paymentId: String, clientToken: String) {
        let id = paymentId.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = clientToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fullMatch(id, pattern: "^[A-Za-z0-9_-]{8,64}$") else {
            throw GbitXPayError.invalidArguments("paymentId is missing or malformed.")
        }
        guard fullMatch(token, pattern: "^[A-Za-z0-9]{16,128}$") else {
            throw GbitXPayError.invalidArguments("clientToken is missing or malformed.")
        }
        return (id, token)
    }

    /// Assert an https URL string and return its canonical origin.
    static func assertHttpsOrigin(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "https",
              let origin = WebViewPolicy.canonicalOrigin(scheme: comps.scheme, host: comps.host, port: comps.port) else {
            throw GbitXPayError.invalidArguments("URL must be a valid https origin.")
        }
        return origin
    }

    /// Build the checkout URL. Args are pre-validated; percent-encode as
    /// belt-and-suspenders. The token rides in the fragment so the page's
    /// hash-capture works, and `embed=native` triggers the native bridge.
    static func buildCheckoutURL(checkoutOrigin: String, paymentId: String, clientToken: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard let id = paymentId.addingPercentEncoding(withAllowedCharacters: allowed),
              let token = clientToken.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "\(checkoutOrigin)/p/\(id)?embed=native#t=\(token)")
    }

    /// True only if `pattern` matches the ENTIRE string (guards against a match
    /// that stops before an embedded newline, e.g. "abc\n").
    static func fullMatch(_ string: String, pattern: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let full = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = re.firstMatch(in: string, options: [], range: full) else { return false }
        return match.range == full
    }
}
