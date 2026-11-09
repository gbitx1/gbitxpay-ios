# Changelog

## 0.2.0 (2026-11-09)

- Default API base is now `https://api.gbitxpay.com` (GbitXPay moved to its own domain). Earlier versions default to `https://gateway.gbitx.com`, which is being retired, so upgrade to keep receiving payments.
- The checkout origin is still whatever `GET /v1/sdk/config` returns (now `https://www.gbitxpay.com`); nothing to configure.
- Docs and homepage: `https://doc.gbitxpay.com`.

## 0.1.0 (2026-07-12)

Initial iOS SDK for GbitXPay.
