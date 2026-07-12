#if canImport(WebKit)
import WebKit

/// `WKUserContentController` STRONG-retains its script-message handler. Passing
/// the view controller (which owns the WebView/config) directly would form a
/// retain cycle: config → userContentController → handler(self) → webView →
/// config, leaking the WebView and leaving a zombie handler that could fire on a
/// torn-down session and defeat the settle latch.
///
/// Registering this weak-forwarding proxy instead breaks the cycle: the
/// controller only strong-holds the proxy through the config it owns, while the
/// proxy holds the real target weakly.
final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
#endif
