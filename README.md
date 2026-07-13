# GbitXPay iOS SDK

Accept crypto payments in your iOS app with **GbitXPay**. Opens the hosted GbitX checkout in a hardened `WKWebView` and returns one typed result.

- One‑line `present()` per payment; `configure()` once at startup.
- No secret key, no address handling, no wallet code ships in your app.
- UIKit + SwiftUI. Zero third‑party dependencies. iOS 15+.

> **Read this first.** Fulfilment is driven **only** by the signed server webhook. The `.confirmed` result is a UX signal — it can be forged on a compromised device. Never release goods from it.

## How it works

Your **server** creates the payment with your **secret** key (`gk_`) and hands the app only `{ paymentId, clientToken }`. The app opens the checkout with a **publishable** key (`pk_`). The signed `PAYMENT_CONFIRMED` webhook is the source of truth.

Two hosts are involved: the SDK validates your publishable key against the API host `gateway.gbitx.com`, which returns the separate, pinned checkout origin `pay.gbitx.com` that the `WKWebView` locks to. They are intentionally different hosts. (`doc.gbitx.com` is the docs site.)

## Install

**Swift Package Manager** (recommended). In Xcode → **File → Add Package Dependencies…**, enter `https://github.com/gbitx1/gbitxpay-ios.git`, and pin **Up to Next Major** from `0.1.0`. Or in a `Package.swift`:
```swift
.package(url: "https://github.com/gbitx1/gbitxpay-ios.git", from: "0.1.0")
```

**CocoaPods.** Published on the CocoaPods trunk:
```ruby
pod 'GbitXPay', '~> 0.1'
```

## Usage — UIKit

```swift
import GbitXPay

// once, e.g. at launch
try await GbitXPay.shared.configure(publishableKey: "pk_live_…")

// per payment — paymentId + clientToken come from YOUR server
let result = try await GbitXPay.shared.present(paymentId: paymentId, clientToken: clientToken)
switch result {
case .confirmed:  showThankYou()      // UX only — fulfil via the webhook
case .cancelled:  break
case .expired:    break
case .failed:     break
}
```

`present()` shows the checkout modally. By default it uses the top‑most view controller; pass `from: yourViewController` to present from a specific host. (A SwiftUI‑only app with no reachable top view controller otherwise throws `invalid_arguments`.)

## Usage — SwiftUI

```swift
@State private var pay = false

var body: some View {
    Button("Pay with crypto") { pay = true }
        .gbitxPayCheckout(isPresented: $pay, paymentId: paymentId, clientToken: clientToken) { result in
            if case .success(.confirmed) = result { showThankYou() }
        }
}
```

## Your server: creating the payment

```bash
curl https://gateway.gbitx.com/v1/payments \
  -H "Authorization: Bearer $GBITX_SECRET_KEY" \
  -H "Content-Type: application/json" \
  -d '{"amount": 49.99, "currency": "USD", "description": "Order #1234"}'
# → { "payment": { "id": "...", "clientToken": "...", ... } }
```
Map the response to the two `present()` arguments: `payment.id` → `paymentId`, `payment.clientToken` → `clientToken`. Send only those two to the app. Fulfil the order from the signed webhook.

## Errors

`present()` / `configure()` throw `GbitXPayError` for SDK/credential faults (a cancelled/expired/failed **payment** is a normal `GbitXPayResult`, not an error). `error.code` is one of: `not_configured`, `invalid_key`, `secret_key_used`, `environment_mismatch`, `onboarding_required`, `merchant_suspended`, `rate_limited`, `network_error`, `server_error`, `invalid_arguments`.

## App Store

Crypto is permitted for **physical goods** and **real‑world services** (Apple Guideline 3.1.1). **Digital goods/services consumed in‑app must use Apple IAP** — don't use this SDK for those.

## Requirements

iOS 15+. Do **not** add an ATS exception (`NSAllowsArbitraryLoads`) on the SDK's behalf — the checkout is HTTPS‑only and the SDK enforces it. See [SECURITY.md](SECURITY.md).

## License

MIT © GBIT TECHNOLOGIES LIMITED COMPANY
