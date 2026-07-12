import XCTest
@testable import GbitXPay

// Unit tests over the pure, WebKit-free core: validation, origin policy, message
// parsing/sanitization, and the config error taxonomy. These are the security-
// critical decisions; they need no WebView.
final class GbitXPayTests: XCTestCase {

    let pkTest = "pk_test_" + String(repeating: "a", count: 64)
    let pkLive = "pk_live_" + String(repeating: "b", count: 64)

    // MARK: - Validation

    func testPublishableKeyAcceptsValidAndInfersEnvironment() throws {
        let (k1, e1) = try Validation.assertPublishableKey(pkTest)
        XCTAssertEqual(k1, pkTest); XCTAssertEqual(e1, .test)
        let (_, e2) = try Validation.assertPublishableKey("  \(pkLive)  ")
        XCTAssertEqual(e2, .live)
    }

    func testSecretKeyRejectedWithoutEcho() {
        let secret = "gk_live_" + String(repeating: "c", count: 64)
        XCTAssertThrowsError(try Validation.assertPublishableKey(secret)) { error in
            guard case GbitXPayError.secretKeyUsed = error else { return XCTFail("wrong error") }
            XCTAssertFalse((error as? GbitXPayError)?.errorDescription?.contains(secret) ?? true)
        }
    }

    func testMalformedKeysRejected() {
        for bad in ["pk_live_xyz", "pk_prod_" + String(repeating: "a", count: 64), "pk_test_" + String(repeating: "a", count: 63), "", "   "] {
            XCTAssertThrowsError(try Validation.assertPublishableKey(bad), bad)
        }
    }

    func testPaymentArgsAnchoredFullMatch() {
        // valid
        XCTAssertNoThrow(try Validation.assertPaymentArgs(paymentId: "ckpayment12345", clientToken: String(repeating: "a", count: 32)))
        // url-breaking / malformed
        let bads: [(String, String)] = [
            ("bad/id", String(repeating: "a", count: 32)),
            ("id#frag", String(repeating: "a", count: 32)),
            ("id?q=1", String(repeating: "a", count: 32)),
            ("short", String(repeating: "a", count: 32)),
            ("okpaymentid", "tooshort"),
            ("okpaymentid\nokpaymentid", String(repeating: "a", count: 32)), // newline injection
        ]
        for (id, tok) in bads {
            XCTAssertThrowsError(try Validation.assertPaymentArgs(paymentId: id, clientToken: tok), "\(id)")
        }
    }

    func testBuildCheckoutURL() {
        let url = Validation.buildCheckoutURL(checkoutOrigin: "https://pay.gbitx.com", paymentId: "pay123456", clientToken: String(repeating: "a", count: 32))
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.hasPrefix("https://pay.gbitx.com/p/pay123456?embed=native#t="))
    }

    // MARK: - WebViewPolicy (exact-origin, look-alike rejection)

    func testOriginPolicyRejectsLookAlikes() {
        let origin = "https://pay.gbitx.com"
        func u(_ s: String) -> URL { URL(string: s)! }
        XCTAssertTrue(WebViewPolicy.mayLoadInWebView(checkoutOrigin: origin, url: u("https://pay.gbitx.com/p/x")))
        XCTAssertTrue(WebViewPolicy.mayLoadInWebView(checkoutOrigin: origin, url: u("https://pay.gbitx.com/assets/a.js")))
        for bad in ["https://pay.gbitx.com.evil.com/p/x", "https://pay.gbitx.company/p/x", "http://pay.gbitx.com/p/x", "https://sub.pay.gbitx.com/p/x"] {
            XCTAssertFalse(WebViewPolicy.mayLoadInWebView(checkoutOrigin: origin, url: u(bad)), bad)
        }
    }

    func testTrustedMessageSourceRequiresPaymentPath() {
        let origin = "https://pay.gbitx.com"
        func u(_ s: String) -> URL { URL(string: s)! }
        XCTAssertTrue(WebViewPolicy.isTrustedMessageSource(checkoutOrigin: origin, url: u("https://pay.gbitx.com/p/abc?x#t=y")))
        XCTAssertFalse(WebViewPolicy.isTrustedMessageSource(checkoutOrigin: origin, url: u("https://pay.gbitx.com/")))
        XCTAssertFalse(WebViewPolicy.isTrustedMessageSource(checkoutOrigin: origin, url: u("https://pay.gbitx.com.evil.com/p/abc")))
    }

    // MARK: - MessageHandler

    func testParseAcceptsKnownAndDropsUnknown() {
        let good = "{\"type\":\"gbitx:payment:confirmed\",\"payment\":{\"id\":\"p1\",\"status\":\"CONFIRMED\",\"amount\":\"10.00\",\"currency\":\"USD\",\"mode\":\"LIVE\",\"expiresAt\":\"z\"}}"
        let parsed = MessageHandler.parse(good)
        XCTAssertEqual(parsed?.type, .confirmed)
        XCTAssertEqual(parsed?.payment?.id, "p1")

        XCTAssertNil(MessageHandler.parse("{\"type\":\"gbitx:payment:hacked\"}"))
        XCTAssertNil(MessageHandler.parse("{not json"))
        XCTAssertNil(MessageHandler.parse("[1,2,3]"))
        XCTAssertNil(MessageHandler.parse(String(repeating: "x", count: 9000)))
        XCTAssertNil(MessageHandler.parse(123))
    }

    func testLoadedMayHaveNoPayment() {
        let parsed = MessageHandler.parse("{\"type\":\"gbitx:payment:loaded\"}")
        XCTAssertEqual(parsed?.type, .loaded)
        XCTAssertNil(parsed?.payment)
    }

    func testSanitizeStripsExtraFieldsAndRejectsBadStatus() {
        let p = MessageHandler.sanitize(["id": "p", "status": "CONFIRMED", "amount": "1", "expiresAt": "z", "address": "bc1qevil", "txHash": "deadbeef", "externalRef": "secret"])
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.amount, "1")
        XCTAssertNil(MessageHandler.sanitize(["id": "p", "status": "HACKED"]))
        XCTAssertNil(MessageHandler.sanitize(["status": "CONFIRMED"]))
    }

    func testDecimalDropsExponential() {
        XCTAssertEqual(MessageHandler.decimalString("0.0003"), "0.0003")
        XCTAssertEqual(MessageHandler.decimalString(10), "10")
        XCTAssertNil(MessageHandler.decimalString(1e-8))
        XCTAssertNil(MessageHandler.decimalString(true))
    }

    func testTerminalMapping() {
        XCTAssertNil(MessageHandler.terminalResult(type: .loaded, payment: nil))
        if case .cancelled = MessageHandler.terminalResult(type: .closed, payment: nil)! {} else { XCTFail() }
        if case .confirmed = MessageHandler.terminalResult(type: .confirmed, payment: nil)! {} else { XCTFail() }
    }

    // MARK: - Config error taxonomy

    func testConfigErrorTaxonomy() {
        if case GbitXPayError.onboardingRequired(let s) = GbitXPayCore.mapConfigError(status: 403, body: ["code": "ONBOARDING_REQUIRED", "onboardingStatus": "PENDING_APPROVAL"], retryAfter: nil) {
            XCTAssertEqual(s, "PENDING_APPROVAL")
        } else { XCTFail() }
        if case GbitXPayError.merchantSuspended = GbitXPayCore.mapConfigError(status: 403, body: [:], retryAfter: nil) {} else { XCTFail() }
        if case GbitXPayError.invalidKey = GbitXPayCore.mapConfigError(status: 401, body: [:], retryAfter: nil) {} else { XCTFail() }
        if case GbitXPayError.rateLimited(let sec) = GbitXPayCore.mapConfigError(status: 429, body: [:], retryAfter: "30") {
            XCTAssertEqual(sec, 30)
        } else { XCTFail() }
        if case GbitXPayError.serverError = GbitXPayCore.mapConfigError(status: 500, body: [:], retryAfter: nil) {} else { XCTFail() }
    }

    func testParseConfigSuccessValidatesShape() {
        let ok = try? GbitXPayCore.parseConfigSuccess(["success": true, "environment": "live", "checkoutBaseUrl": "https://pay.gbitx.com", "merchant": ["name": "Acme"]])
        XCTAssertEqual(ok?.environment, .live)
        XCTAssertEqual(ok?.checkoutOrigin, "https://pay.gbitx.com")
        XCTAssertThrowsError(try GbitXPayCore.parseConfigSuccess(["success": false]))
        XCTAssertThrowsError(try GbitXPayCore.parseConfigSuccess(["success": true, "environment": "prod", "checkoutBaseUrl": "https://pay.gbitx.com", "merchant": [:]]))
        XCTAssertThrowsError(try GbitXPayCore.parseConfigSuccess(["success": true, "environment": "live", "checkoutBaseUrl": "http://pay.gbitx.com", "merchant": [:]]))
    }
}
