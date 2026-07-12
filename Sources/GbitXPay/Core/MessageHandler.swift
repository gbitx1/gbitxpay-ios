import Foundation

/// Pure parse / sanitize / map of bridge messages. Never throws; callers must
/// have already verified the message origin (frame securityOrigin + committed
/// `/p/` path) before invoking.
enum MessageHandler {

    static let maxBytes = 8192

    static let knownTypes: [String: CheckoutEventType] = [
        "gbitx:payment:loaded": .loaded,
        "gbitx:payment:confirmed": .confirmed,
        "gbitx:payment:cancelled": .cancelled,
        "gbitx:payment:expired": .expired,
        "gbitx:payment:failed": .failed,
        "gbitx:payment:closed": .closed,
    ]

    private static let statuses: Set<String> = [
        "PENDING", "AWAITING_PAYMENT", "UNDERPAID", "CONFIRMING",
        "CONFIRMED", "EXPIRED", "FAILED", "CANCELLED",
    ]

    struct Parsed {
        let type: CheckoutEventType
        let payment: SanitizedPayment?
    }

    /// `body` is `WKScriptMessage.body`. Require a String, size-cap it, parse as a
    /// JSON object, map a known type, and sanitize the payment. Any deviation → nil.
    static func parse(_ body: Any?) -> Parsed? {
        guard let string = body as? String, !string.isEmpty, string.utf8.count <= maxBytes else { return nil }
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: Any] else { return nil }
        guard let typeString = dict["type"] as? String, let type = knownTypes[typeString] else { return nil }
        return Parsed(type: type, payment: sanitize(dict["payment"]))
    }

    /// Re-pick ONLY whitelisted fields into a fresh struct. Drops address/txHash/
    /// externalRef and any other keys. nil if unusable (no id / unknown status).
    static func sanitize(_ input: Any?) -> SanitizedPayment? {
        guard let p = input as? [String: Any] else { return nil }
        guard let id = p["id"] as? String,
              let statusString = p["status"] as? String,
              statuses.contains(statusString),
              let status = PaymentStatus(rawValue: statusString) else { return nil }

        let mode: String = {
            if let m = p["mode"] as? String, m == "LIVE" || m == "SANDBOX" { return m }
            return "SANDBOX"
        }()

        return SanitizedPayment(
            id: id,
            status: status,
            amount: decimalString(p["amount"]) ?? "",
            currency: p["currency"] as? String ?? "",
            crypto: p["crypto"] as? String,
            network: p["network"] as? String,
            amountCrypto: decimalString(p["amountCrypto"]),
            amountPaid: decimalString(p["amountPaid"]),
            mode: mode,
            confirmedAt: p["confirmedAt"] as? String,
            expiresAt: p["expiresAt"] as? String ?? ""
        )
    }

    /// String or finite non-exponential number → plain string. Exponential
    /// (e.g. 1e-8 / 1e21) and booleans drop to nil rather than surface a
    /// misleading "1e-8" — the field is display-only.
    static func decimalString(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        guard let n = value as? NSNumber else { return nil }
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
        guard n.doubleValue.isFinite else { return nil }
        let s = n.stringValue
        return (s.contains("e") || s.contains("E")) ? nil : s
    }

    /// Map a terminal event to a result. `loaded` is non-terminal → nil.
    static func terminalResult(type: CheckoutEventType, payment: SanitizedPayment?) -> GbitXPayResult? {
        switch type {
        case .confirmed:            return .confirmed(payment: payment)
        case .cancelled, .closed:   return .cancelled(reason: .userClosed, payment: payment)
        case .expired:              return .expired(reason: .expired, payment: payment)
        case .failed:               return .failed(payment: payment)
        case .loaded:               return nil
        }
    }
}
