#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI

public extension View {
    /// Present the GbitXPay checkout when `isPresented` becomes true. Resolves via
    /// `onResult` with the terminal `GbitXPayResult` (success) or a `GbitXPayError`
    /// (failure), and flips `isPresented` back to false. Funnels into the same
    /// controller as the imperative `GbitXPay.shared.present`, preserving the
    /// single-active-session and single-settle invariants.
    ///
    ///     .gbitxPayCheckout(isPresented: $pay, paymentId: id, clientToken: token) { result in
    ///         if case .success(.confirmed) = result { showThankYou() }
    ///     }
    func gbitxPayCheckout(isPresented: Binding<Bool>,
                          paymentId: String,
                          clientToken: String,
                          onResult: @escaping (Result<GbitXPayResult, Error>) -> Void) -> some View {
        modifier(GbitXPayCheckoutModifier(isPresented: isPresented,
                                          paymentId: paymentId,
                                          clientToken: clientToken,
                                          onResult: onResult))
    }
}

private struct GbitXPayCheckoutModifier: ViewModifier {
    @Binding var isPresented: Bool
    let paymentId: String
    let clientToken: String
    let onResult: (Result<GbitXPayResult, Error>) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: isPresented) { presented in
            guard presented else { return }
            Task { @MainActor in
                do {
                    let result = try await GbitXPay.shared.present(paymentId: paymentId, clientToken: clientToken)
                    isPresented = false
                    onResult(.success(result))
                } catch {
                    isPresented = false
                    onResult(.failure(error))
                }
            }
        }
    }
}
#endif
