# Security

The GbitXPay iOS SDK opens the hosted checkout in a hardened `WKWebView`. This document states the trust model, what the SDK enforces, and the residual risks it cannot close alone. It mirrors the React Native SDK's security posture, re‑expressed for WKWebView.

## The one invariant

**Fulfilment is driven only by the signed server webhook** (`PAYMENT_CONFIRMED`) or a server‑side `GET /v1/payments/:id` with your **secret** key. The `.confirmed` result is a UX signal, not proof of payment. This bounds the blast radius of every residual risk.

## What the SDK enforces

- **Pinned origin.** The checkout origin comes from your validated `GET /v1/sdk/config`, is asserted `https`, and is frozen. `present()` cannot override it.
- **Sole‑gate navigation lock.** WKWebView has no `originWhitelist`; `WKNavigationDelegate.decidePolicyFor` is the sole gate and `.allow`s only the exact pinned origin over https (exact scheme+host+port, never prefix). Everything else is `.cancel`led and opened **nowhere** — the SDK contains no `UIApplication.open`, `SFSafariViewController`, or deep‑link path, so a compromised page cannot force‑launch a URL or wallet scheme.
- **Authenticated message gate.** Bridge messages are trusted only when `message.frameInfo.isMainFrame` is true and `frameInfo.securityOrigin` (WebKit‑authenticated, unspoofable) exactly equals the pinned origin, AND the committed main‑frame URL (`didCommit`) is on a `/p/` path — plus the payload is bound to the active `paymentId`.
- **Defensive parsing.** Bridge payloads are size‑capped, parsed in a guard, mapped against a known event set, and re‑picked into a fresh struct holding only the whitelisted payment fields (no `address`, `txHash`, `externalRef`).
- **Single settle.** Exactly‑once resolution (a double‑resume of the continuation would crash). Every dismissal path settles once — close button, interactive swipe (`presentationControllerDidDismiss`), programmatic teardown, and a **fixed 65‑minute client backstop** (just beyond the 60‑minute server payment expiry; never derived from a page payload).
- **No retain‑cycle leak.** The `WKScriptMessageHandler` is registered through a weak‑forwarding proxy and removed on teardown, so no zombie handler survives a torn‑down session.
- **WebView lockdown.** Non‑persistent website data store (cookie isolation), no file access, no child windows (`createWebViewWith` → nil), `javaScriptCanOpenWindowsAutomatically = false`, media capture denied, `allowsLinkPreview = false`, no injected token (it rides only in the URL fragment).
- **Credential hygiene.** The key, token, and full URL never reach a log (not even `os_log`). On settle the token‑bearing URL is dropped — the `WKWebView` holding its request is torn down and released and the pending‑URL reference is niled — so no strong reference to the token survives a finished session. Nothing is persisted.
- **No secret key.** A `gk_` key is rejected with `secretKeyUsed` before any network call.

## Residual risks (cannot be closed client‑side)

1. **A compromised checkout origin can emit a forged `.confirmed`.** If `pay.gbitx.com` itself is compromised or MITM'd, a same‑origin page can send any bridge event. **Mitigation: webhook‑is‑truth.** TLS + the origin lock prevent MITM.
2. **App‑Bound Domains** (`WKAppBoundDomains` + `limitsNavigationsToAppBoundDomains`) is an optional OS‑enforced origin lock the SDK does not force — it requires host‑app `Info.plist` entries and constrains other WebViews in the app. Enable it if that fits your app. (If enabled **without** listing the host, WKWebView silently disables `messageHandlers` and breaks the bridge.)
3. **TLS public‑key pinning** for `pay.gbitx.com` is a recommended opt‑in fast‑follow, not enabled by default (to avoid bricking on cert rotation).

## Reporting a vulnerability

Email **security@gbitx.com**. Please do not open a public issue.
