import Foundation

/// The single public error type. Terminal payment outcomes (cancelled / expired
/// / failed) are NOT errors — they resolve as a `GbitXPayResult`. Throw only for
/// SDK or credential faults.
///
/// No case carries the publishable key, client token, or the token-bearing URL.
/// A transport error is deliberately NOT stored as an associated value so a crash
/// reporter walking the error can never surface it (mirrors the RN SDK's
/// non-enumerable `cause`).
public enum GbitXPayError: Error, LocalizedError, Sendable {
    /// `present()` called before a successful `configure()`.
    case notConfigured
    /// Publishable key wrong/revoked/malformed, or a config 4xx.
    case invalidKey
    /// A SECRET key (`gk_`) was passed to the SDK.
    case secretKeyUsed
    /// Key environment and server environment disagree.
    case environmentMismatch
    /// Merchant not yet approved for this live key.
    case onboardingRequired(status: String?)
    /// Merchant account suspended.
    case merchantSuspended
    /// Config endpoint rate-limited.
    case rateLimited(retryAfterSec: Int?)
    /// Could not reach GbitX (offline / DNS / TLS / timeout).
    case networkError
    /// GbitX reachable but returned 5xx or an unusable body.
    case serverError
    /// Bad arguments (malformed id/token, or a checkout already open).
    case invalidArguments(String)

    /// Stable machine code (mirrors the RN SDK's `GbitXPayErrorCode`).
    public var code: String {
        switch self {
        case .notConfigured:      return "not_configured"
        case .invalidKey:         return "invalid_key"
        case .secretKeyUsed:      return "secret_key_used"
        case .environmentMismatch: return "environment_mismatch"
        case .onboardingRequired: return "onboarding_required"
        case .merchantSuspended:  return "merchant_suspended"
        case .rateLimited:        return "rate_limited"
        case .networkError:       return "network_error"
        case .serverError:        return "server_error"
        case .invalidArguments:   return "invalid_arguments"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Call and await GbitXPay.shared.configure(publishableKey:) before present()."
        case .invalidKey:
            return "The publishable key was rejected."
        case .secretKeyUsed:
            return "A SECRET key (gk_) was passed to the SDK. Use a publishable key (pk_) only, and remove the secret key from your app immediately."
        case .environmentMismatch:
            return "The publishable key environment and the server environment disagree."
        case .onboardingRequired:
            return "This live publishable key is not active yet. Complete onboarding to activate."
        case .merchantSuspended:
            return "This merchant account is not active."
        case .rateLimited:
            return "Too many requests. Please try again shortly."
        case .networkError:
            return "Could not reach GbitXPay to validate the publishable key."
        case .serverError:
            return "GbitXPay is temporarily unavailable. Please try again."
        case .invalidArguments(let message):
            return message
        }
    }
}
