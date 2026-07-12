import Foundation

/// Thread-safe state machine + config validation. On native this is a REAL data
/// race surface (unlike the RN single JS thread), so all state lives inside an
/// actor and a superseded configure() run can never install a stale
/// checkoutOrigin (the trust root).
actor GbitXPayCore {

    static let shared = GbitXPayCore()

    private enum State { case unconfigured, configuring, configured, failed }
    private var state: State = .unconfigured
    private var config: ResolvedConfig?
    private var inflightTask: Task<ResolvedConfig, Error>?
    private var inflightKey: String?
    private var currentRunId: UUID?

    private static let defaultApiBase = "https://gateway.gbitx.com"
    private static let defaultTimeout: TimeInterval = 10
    private static let minTimeout: TimeInterval = 1
    private static let maxTimeout: TimeInterval = 60

    /// The resolved config iff fully configured.
    func currentConfig() -> ResolvedConfig? {
        state == .configured ? config : nil
    }

    func configure(publishableKey rawKey: String,
                   environment explicitEnv: GbitXPayEnvironment?,
                   timeout: TimeInterval,
                   apiBaseURL: String?,
                   debug: Bool) async throws {
        if debug { Redact.setDebug(true) }

        let (key, prefixEnv) = try Validation.assertPublishableKey(rawKey)
        if let e = explicitEnv, e != prefixEnv { throw GbitXPayError.environmentMismatch }

        let clamped = min(Self.maxTimeout, max(Self.minTimeout, timeout.isFinite ? timeout : Self.defaultTimeout))
        let apiBase = try apiBaseURL.map { try Validation.assertHttpsOrigin($0) } ?? Self.defaultApiBase

        // Share an in-flight configure for the same key.
        if let task = inflightTask, inflightKey == key {
            _ = try await task.value
            return
        }

        state = .configuring
        let runId = UUID()
        currentRunId = runId
        Redact.log("configure: validating key against", "\(apiBase)/v1/sdk/config")

        let task = Task<ResolvedConfig, Error> {
            try await Self.fetchConfig(key: key, prefixEnv: prefixEnv, explicitEnv: explicitEnv, apiBase: apiBase, timeout: clamped)
        }
        inflightTask = task
        inflightKey = key

        defer {
            // Clear in-flight only if this run still owns it.
            if currentRunId == runId {
                inflightTask = nil
                inflightKey = nil
            }
        }

        do {
            let resolved = try await task.value
            // Commit only if still the current run (a later configure may have superseded us).
            if currentRunId == runId {
                config = resolved
                state = .configured
                Redact.log("configure: ok, environment =", resolved.environment.rawValue)
            }
        } catch {
            if currentRunId == runId {
                state = .failed
                config = nil
            }
            throw error
        }
    }

    // MARK: - Network + parsing (pure, static, testable)

    static func fetchConfig(key: String,
                            prefixEnv: GbitXPayEnvironment,
                            explicitEnv: GbitXPayEnvironment?,
                            apiBase: String,
                            timeout: TimeInterval) async throws -> ResolvedConfig {
        guard let url = URL(string: "\(apiBase)/v1/sdk/config") else {
            throw GbitXPayError.invalidArguments("Invalid API base URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GbitXPayError.networkError
        }

        guard let http = response as? HTTPURLResponse else { throw GbitXPayError.serverError }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200...299).contains(http.statusCode) else {
            throw mapConfigError(status: http.statusCode, body: body,
                                 retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }

        let parsed = try parseConfigSuccess(body)
        if parsed.environment != prefixEnv { throw GbitXPayError.environmentMismatch }
        if let e = explicitEnv, e != parsed.environment { throw GbitXPayError.environmentMismatch }

        return ResolvedConfig(publishableKey: key,
                              environment: parsed.environment,
                              checkoutOrigin: parsed.checkoutOrigin,
                              merchant: parsed.merchant)
    }

    /// Map a non-2xx config response to a typed error (mirrors the RN taxonomy).
    static func mapConfigError(status: Int, body: [String: Any]?, retryAfter: String?) -> GbitXPayError {
        let code = body?["code"] as? String
        if status == 403, code == "ONBOARDING_REQUIRED" {
            return .onboardingRequired(status: body?["onboardingStatus"] as? String)
        }
        if status == 403 { return .merchantSuspended }
        if status == 429 {
            let sec = retryAfter.flatMap { Int($0) }
            return .rateLimited(retryAfterSec: (sec.map { $0 > 0 } ?? false) ? sec : nil)
        }
        if status >= 500 { return .serverError }
        return .invalidKey
    }

    /// Validate a 2xx body shape so "configured" means the real backend answered
    /// (a captive-portal / CDN 200 with junk maps to serverError, never accepted).
    static func parseConfigSuccess(_ body: [String: Any]?) throws -> (environment: GbitXPayEnvironment, checkoutOrigin: String, merchant: MerchantInfo) {
        guard let body, body["success"] as? Bool == true else { throw GbitXPayError.serverError }
        guard let envString = body["environment"] as? String,
              let environment = GbitXPayEnvironment(rawValue: envString) else { throw GbitXPayError.serverError }
        guard let baseURL = body["checkoutBaseUrl"] as? String,
              let origin = try? Validation.assertHttpsOrigin(baseURL) else { throw GbitXPayError.serverError }
        guard let merchant = body["merchant"] as? [String: Any] else { throw GbitXPayError.serverError }
        let rawName = merchant["name"] as? String
        let name = (rawName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Merchant"
        let website = (merchant["website"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return (environment, origin, MerchantInfo(name: name, website: website))
    }
}
