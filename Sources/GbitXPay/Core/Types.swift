import Foundation

/// Live or test environment, inferred from the publishable key prefix and
/// cross-checked against the server.
public enum GbitXPayEnvironment: String, Sendable {
    case live
    case test
}

/// Mirrors the server PaymentStatus enum.
public enum PaymentStatus: String, Sendable {
    case pending = "PENDING"
    case awaitingPayment = "AWAITING_PAYMENT"
    case underpaid = "UNDERPAID"
    case confirming = "CONFIRMING"
    case confirmed = "CONFIRMED"
    case expired = "EXPIRED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
}

/// Exactly the fields the checkout page emits (serializePayment). `address`,
/// `txHash`, and `externalRef` are intentionally absent — never readable
/// client-side. Amounts are decimal-safe strings.
public struct SanitizedPayment: Sendable, Equatable {
    public let id: String
    public let status: PaymentStatus
    public let amount: String
    public let currency: String
    public let crypto: String?
    public let network: String?
    public let amountCrypto: String?
    public let amountPaid: String?
    public let mode: String            // "LIVE" | "SANDBOX"
    public let confirmedAt: String?
    public let expiresAt: String
}

public enum CancelReason: String, Sendable {
    case userClosed
    case dismissed
    case backButton
    case loadFailed
}

public enum ExpiredReason: String, Sendable {
    case expired
    case clientBackstop
}

/// The terminal outcome of a checkout. NOT an error — a cancelled/expired/failed
/// payment is a normal result. `payment` is populated in practice for confirmed
/// checkouts but is optional because a bridge message is device-controllable and
/// UX-only: fulfilment is driven by the signed server webhook.
public enum GbitXPayResult: Sendable {
    case confirmed(payment: SanitizedPayment?)
    case cancelled(reason: CancelReason, payment: SanitizedPayment?)
    case expired(reason: ExpiredReason, payment: SanitizedPayment?)
    case failed(payment: SanitizedPayment?)
}

public enum CheckoutEventType: String, Sendable {
    case loaded, confirmed, cancelled, expired, failed, closed
}

/// A streamed lifecycle event (UX/analytics only).
public struct GbitXPayCheckoutEvent: Sendable {
    public let type: CheckoutEventType
    public let payment: SanitizedPayment?
}

public struct MerchantInfo: Sendable, Equatable {
    public let name: String
    public let website: String?
}

/// Non-sensitive resolved configuration. `checkoutOrigin` is the frozen root of
/// trust for the navigation lock and the message gate.
struct ResolvedConfig: Sendable {
    let publishableKey: String
    let environment: GbitXPayEnvironment
    let checkoutOrigin: String
    let merchant: MerchantInfo
}

/// One active checkout session.
struct CheckoutSession: Sendable {
    let paymentId: String
    let clientToken: String
    let url: URL
    let checkoutOrigin: String
    let merchant: MerchantInfo
}
