#if canImport(UIKit)
import UIKit
import WebKit

/// Hosts the hardened WKWebView for one checkout session and resolves exactly
/// one `GbitXPayResult`. All WebView work happens on the main thread.
@MainActor
final class CheckoutViewController: UIViewController {

    private let paymentId: String
    private let merchantName: String
    private let checkoutOrigin: String
    private let onLoaded: (@MainActor () -> Void)?
    private let onEvent: (@MainActor (GbitXPayCheckoutEvent) -> Void)?
    private let onSettle: (GbitXPayResult) -> Void

    /// The token‑bearing checkout URL (carries `#t=<token>` in its fragment).
    /// Held only until the initial load and niled on settle, so no strong
    /// reference to the token survives a finished session.
    private var pendingURL: URL?

    private var webView: WKWebView!
    private var messageProxy: WeakScriptMessageProxy?

    private var settled = false
    private var loadedFired = false
    private var committedURL: URL?
    private var backstop: DispatchWorkItem?

    // UI
    private let header = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)
    private var errorView: UIView?

    /// Fixed session ceiling — server payment expires at 60m, +5m grace. NEVER
    /// derived from a page/message payload.
    private static let backstopSeconds: TimeInterval = 65 * 60

    init(session: CheckoutSession,
         onLoaded: (@MainActor () -> Void)?,
         onEvent: (@MainActor (GbitXPayCheckoutEvent) -> Void)?,
         onSettle: @escaping (GbitXPayResult) -> Void) {
        // Copy out only what the controller needs for its lifetime. The
        // token‑bearing URL goes into a niable var; the rest are non‑sensitive.
        // The CheckoutSession (and its clientToken) is not retained past init.
        self.paymentId = session.paymentId
        self.merchantName = session.merchant.name
        self.checkoutOrigin = session.checkoutOrigin
        self.pendingURL = session.url
        self.onLoaded = onLoaded
        self.onEvent = onEvent
        self.onSettle = onSettle
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        presentationController?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        buildChrome()
        buildWebView()
        armBackstop()
        guard let url = pendingURL else { return }
        Redact.log("present", Redact.redactURL(url.absoluteString))
        webView.load(URLRequest(url: url))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Catch-all: any dismissal not already handled (e.g. the host app dismissed
        // us) still settles exactly once so the awaiting call never hangs.
        if !settled, isBeingDismissed || isMovingFromParent || presentingViewController == nil {
            settle(.cancelled(reason: .dismissed, payment: nil))
        }
    }

    // MARK: - Settle (single exit)

    func settle(_ result: GbitXPayResult) {
        guard !settled else { return }
        settled = true
        backstop?.cancel()
        backstop = nil
        teardownWebView()
        committedURL = nil
        pendingURL = nil            // drop the last strong reference to the token URL
        onSettle(result)
        if presentingViewController != nil {
            dismiss(animated: true)
        }
    }

    private func armBackstop() {
        let work = DispatchWorkItem { [weak self] in
            self?.settle(.expired(reason: .clientBackstop, payment: nil))
        }
        backstop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.backstopSeconds, execute: work)
    }

    private func teardownWebView() {
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: BridgeName.value)
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
        // Release the WKWebView so its retained URLRequest — which carries the
        // token in the URL fragment — is dropped immediately, not at dealloc.
        webView = nil
    }

    // MARK: - WebView construction (hardened)

    private func buildWebView() {
        let config = WKWebViewConfiguration()
        // Cookie/website-data isolation from the host app. sessionStorage (used by
        // the page's cancel-token capture) still functions in a non-persistent store.
        config.websiteDataStore = .nonPersistent()
        config.userContentController = WKUserContentController()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.dataDetectorTypes = []

        let proxy = WeakScriptMessageProxy(target: self)
        messageProxy = proxy
        config.userContentController.add(proxy, name: BridgeName.value)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsLinkPreview = false
        wv.allowsBackForwardNavigationGestures = false
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.backgroundColor = Theme.background
        wv.isOpaque = false
        // Never expose the token‑bearing checkout to Web Inspector. Web Inspector
        // defaults ON for DEBUG host‑app builds on iOS 16.4+, so lock it off here
        // regardless of how the merchant builds their app.
        if #available(iOS 16.4, *) { wv.isInspectable = false }
        view.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: header.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        webView = wv

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = Theme.spinner
        spinner.startAnimating()
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: wv.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: wv.centerYAnchor),
        ])
    }

    private func buildChrome() {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = Theme.background
        view.addSubview(header)

        titleLabel.text = merchantName
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = Theme.text
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .regular)
        closeButton.tintColor = Theme.text
        closeButton.accessibilityLabel = "Close checkout"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(titleLabel)
        header.addSubview(closeButton)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),
        ])
    }

    @objc private func closeTapped() {
        settle(.cancelled(reason: .userClosed, payment: nil))
    }

    private func hideSpinner() {
        spinner.stopAnimating()
        spinner.isHidden = true
    }

    // MARK: - Error UI

    private func showLoadError() {
        guard errorView == nil, !settled else { return }
        hideSpinner()
        webView?.isHidden = true

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = Theme.background

        let title = UILabel()
        title.text = "Could not load checkout"
        title.font = .systemFont(ofSize: 16, weight: .medium)
        title.textColor = Theme.text
        title.textAlignment = .center

        let sub = UILabel()
        sub.text = "Check your connection and try again."
        sub.font = .systemFont(ofSize: 13)
        sub.textColor = Theme.subtle
        sub.textAlignment = .center
        sub.numberOfLines = 0

        let retry = UIButton(type: .system)
        retry.setTitle("Retry", for: .normal)
        retry.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let close = UIButton(type: .system)
        close.setTitle("Close", for: .normal)
        close.setTitleColor(Theme.subtle, for: .normal)
        close.addTarget(self, action: #selector(errorCloseTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, sub, retry, close])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: header.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32),
        ])
        errorView = container
    }

    @objc private func retryTapped() {
        errorView?.removeFromSuperview()
        errorView = nil
        webView?.isHidden = false
        spinner.isHidden = false
        spinner.startAnimating()
        webView?.reload()
    }

    @objc private func errorCloseTapped() {
        settle(.cancelled(reason: .loadFailed, payment: nil))
    }

    private func isMainFrameFailure(_ url: URL?) -> Bool {
        guard let url else { return true }
        return WebViewPolicy.isTrustedMessageSource(checkoutOrigin: checkoutOrigin, url: url)
    }
}

// MARK: - Navigation lock (sole gate)

extension CheckoutViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                decidePolicyFor navigationAction: WKNavigationAction,
                preferences: WKWebpagePreferences,
                decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        guard let url = navigationAction.request.url,
              WebViewPolicy.mayLoadInWebView(checkoutOrigin: checkoutOrigin, url: url) else {
            // Off-origin or non-https: block, open NOTHING externally.
            decisionHandler(.cancel, preferences)
            return
        }
        preferences.allowsContentJavaScript = true
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        committedURL = webView.url
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideSpinner()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if isBenignNavError(error) { return }
        if isMainFrameFailure(webView.url) { showLoadError() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // A navigation we deliberately .cancel'd (off-origin) surfaces here as a
        // cancellation / frame-load-interrupted error — not a real load failure.
        if isBenignNavError(error) { return }
        if isMainFrameFailure((error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? webView.url) {
            showLoadError()
        }
    }

    private func isBenignNavError(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return true }
        // WebKitErrorDomain: 102 = frame load interrupted by policy change (our .cancel).
        if e.domain == "WebKitErrorDomain" && (e.code == 102 || e.code == 101) { return true }
        return false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Renderer died — never blind-reload into an unknown state.
        showLoadError()
    }
}

// MARK: - UI delegate (no child windows, deny media)

extension CheckoutViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                createWebViewWith configuration: WKWebViewConfiguration,
                for navigationAction: WKNavigationAction,
                windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Never open a child WebView / target=_blank. Return nil, open nothing.
        return nil
    }

    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView,
                requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                initiatedByFrame frame: WKFrameInfo,
                type: WKMediaCaptureType,
                decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
}

// MARK: - Message bridge (authenticated origin + committed /p/ + paymentId binding)

extension CheckoutViewController: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard !settled, message.name == BridgeName.value else { return }

        // 1. Authenticated sender origin (WebKit-set, unspoofable).
        let frame = message.frameInfo
        guard frame.isMainFrame else { return }
        let sec = frame.securityOrigin
        let senderOrigin = WebViewPolicy.canonicalOrigin(scheme: sec.protocol,
                                                         host: sec.host,
                                                         port: sec.port == 0 ? nil : sec.port)
        guard senderOrigin == checkoutOrigin else { return }

        // 2. Committed main-frame URL must be on a /p/ path of the pinned origin
        //    (WKSecurityOrigin has no path, so this comes from didCommit).
        guard let committed = committedURL,
              WebViewPolicy.isTrustedMessageSource(checkoutOrigin: checkoutOrigin, url: committed) else { return }

        // 3. Parse + sanitize.
        guard let parsed = MessageHandler.parse(message.body) else { return }

        // 4. Bind to THIS payment.
        if let payment = parsed.payment, payment.id != paymentId { return }

        onEvent?(GbitXPayCheckoutEvent(type: parsed.type, payment: parsed.payment))

        if parsed.type == .loaded {
            hideSpinner()
            if !loadedFired { loadedFired = true; onLoaded?() }
            return
        }
        if let result = MessageHandler.terminalResult(type: parsed.type, payment: parsed.payment) {
            settle(result)
        }
    }
}

// MARK: - Swipe-to-dismiss

extension CheckoutViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        settle(.cancelled(reason: .dismissed, payment: nil))
    }
}

/// The bridge name is the cross-SDK wire contract (PaymentPage.jsx emits to
/// `window.webkit.messageHandlers.gbitxpay`). MUST NOT be renamed.
enum BridgeName {
    static let value = "gbitxpay"
}

private enum Theme {
    static var background: UIColor { UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.039, alpha: 1) : .white } }
    static var text: UIColor { UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.95, alpha: 1) : UIColor(white: 0.039, alpha: 1) } }
    static var subtle: UIColor { UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.6, alpha: 1) : UIColor(white: 0.36, alpha: 1) } }
    static var spinner: UIColor { UIColor(red: 0.03, green: 0.51, blue: 0.12, alpha: 1) }
}
#endif
