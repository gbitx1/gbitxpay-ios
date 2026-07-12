import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The GbitXPay iOS SDK.
///
/// Your SERVER creates the payment with your SECRET key and hands the app only
/// `{ paymentId, clientToken }`. The app opens the hosted checkout with this SDK
/// using a PUBLISHABLE key. Fulfilment is driven by the signed server webhook —
/// the `.confirmed` result is a UX signal only and can be forged on a
/// compromised device. Never release goods from it.
///
///     try await GbitXPay.shared.configure(publishableKey: "pk_live_…")
///     let result = try await GbitXPay.shared.present(paymentId: id, clientToken: token)
///     if case .confirmed = result { showThankYou() }   // …but fulfil via the webhook
public final class GbitXPay {

    public static let shared = GbitXPay()
    private init() {}

    /// Validate the publishable key against the GbitX backend and prepare the SDK.
    /// Must complete before `present()`. Safe to call more than once.
    ///
    /// - Throws: `GbitXPayError` on an invalid/secret key, environment mismatch,
    ///   onboarding/suspension, rate limiting, or network/server failure.
    public func configure(publishableKey: String,
                          environment: GbitXPayEnvironment? = nil,
                          timeout: TimeInterval = 10,
                          apiBaseURL: String? = nil,
                          debug: Bool = false) async throws {
        try await GbitXPayCore.shared.configure(publishableKey: publishableKey,
                                                environment: environment,
                                                timeout: timeout,
                                                apiBaseURL: apiBaseURL,
                                                debug: debug)
    }

    #if canImport(UIKit)
    @MainActor private var isPresenting = false
    @MainActor private weak var activeController: CheckoutViewController?

    /// Dismiss the currently-presented checkout, if any, settling it as a user
    /// cancellation. Used by the Flutter plugin's `cancel()` and hot-restart
    /// reconciliation. No-op when nothing is presented.
    @MainActor
    public func dismissActiveCheckout() {
        activeController?.settle(.cancelled(reason: .dismissed, payment: nil))
    }

    /// Open the hosted checkout for one payment and resolve its terminal result.
    ///
    /// - Parameters:
    ///   - paymentId / clientToken: from your server's `POST /v1/payments` response.
    ///   - presenter: the view controller to present from. If nil, the top-most
    ///     view controller is used.
    ///   - onLoaded: fired once when the checkout is interactive (UX only).
    ///   - onEvent: streams every lifecycle event (UX only).
    /// - Returns: a `GbitXPayResult` (confirmed / cancelled / expired / failed).
    /// - Throws: `GbitXPayError` only for SDK/credential faults (never a terminal outcome).
    @MainActor
    public func present(paymentId: String,
                        clientToken: String,
                        from presenter: UIViewController? = nil,
                        onLoaded: (@MainActor () -> Void)? = nil,
                        onEvent: (@MainActor (GbitXPayCheckoutEvent) -> Void)? = nil) async throws -> GbitXPayResult {
        guard let config = await GbitXPayCore.shared.currentConfig() else {
            throw GbitXPayError.notConfigured
        }
        let (paymentId, clientToken) = try Validation.assertPaymentArgs(paymentId: paymentId, clientToken: clientToken)

        guard !isPresenting else {
            throw GbitXPayError.invalidArguments("A checkout is already open.")
        }
        guard let url = Validation.buildCheckoutURL(checkoutOrigin: config.checkoutOrigin,
                                                    paymentId: paymentId,
                                                    clientToken: clientToken) else {
            throw GbitXPayError.invalidArguments("Could not build the checkout URL.")
        }
        guard let host = presenter ?? Self.topViewController() else {
            throw GbitXPayError.invalidArguments("No view controller is available to present from.")
        }

        isPresenting = true
        defer { isPresenting = false }

        let session = CheckoutSession(paymentId: paymentId,
                                      clientToken: clientToken,
                                      url: url,
                                      checkoutOrigin: config.checkoutOrigin,
                                      merchant: config.merchant)

        return await withCheckedContinuation { (continuation: CheckedContinuation<GbitXPayResult, Never>) in
            let controller = CheckoutViewController(session: session,
                                                    onLoaded: onLoaded,
                                                    onEvent: onEvent) { result in
                continuation.resume(returning: result)
            }
            self.activeController = controller
            host.present(controller, animated: true) {
                // Safety net: if UIKit did not actually attach the controller
                // (e.g. the host was mid-transition), settle so present() can
                // never hang forever.
                Task { @MainActor in
                    if controller.presentingViewController == nil, controller.viewIfLoaded?.window == nil {
                        controller.settle(.cancelled(reason: .dismissed, payment: nil))
                    }
                }
            }
        }
    }

    /// Find the top-most presented view controller from the active window scene.
    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let window = (scenes.first ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)?
            .windows.first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    #endif
}
