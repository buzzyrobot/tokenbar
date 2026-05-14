import Foundation
import WebKit
import AppKit

struct CodexUsage {
    var usedPercent: Double?
    var limitReached: Bool = false
    var planType: String?
    var lastUpdated: Date?
    var error: String?
    var accountName: String?
}

@MainActor
class CodexFetcher: NSObject, ObservableObject {
    static let shared = CodexFetcher()

    @Published var usage = CodexUsage()
    @Published var isLoading = false
    @Published var needsLogin = false
    @Published var isInitialized = false

    private var webView: WKWebView!
    private var window: NSWindow!
    private var refreshTimer: Timer?
    private var windowDelegate: LoginWindowDelegate?
    private var loginDelegate: OpenAILoginDelegate?
    private var loginCompleted = false
    private var windowOpenedAt: Date = .distantPast

    override private init() {
        super.init()
        setupWebView()
        Task { await startUp() }
    }

    private func setupWebView() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: .init(x: 0, y: 0, width: 960, height: 700), configuration: cfg)

        window = NSWindow(
            contentRect: .init(x: -50000, y: -50000, width: 960, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView

        // Użytkownik zamknął okno ręcznie — odśwież dane
        windowDelegate = LoginWindowDelegate { [weak self] in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        window.delegate = windowDelegate
    }

    // MARK: - Lifecycle

    private func startUp() async {
        // Delay startup so UsageFetcher finishes navigating to claude.ai first
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await doFetch()
        isInitialized = true
        scheduleRefresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await doFetch()
    }

    // MARK: - Login window

    func showLoginWindow() {
        if window.styleMask.contains(.titled) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        loginCompleted = false
        windowOpenedAt = Date()

        window.setFrame(.init(x: 0, y: 0, width: 960, height: 700), display: false)
        window.styleMask = [.titled, .closable, .resizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window.title = String(localized: "chatgpt_login_title")
        loginDelegate = OpenAILoginDelegate { [weak self] url in
            self?.handlePostLoginURL(url)
        }
        webView.navigationDelegate = loginDelegate
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/codex")!))
    }

    private func handlePostLoginURL(_ url: URL) {
        guard Date().timeIntervalSince(windowOpenedAt) > 5 else { return }
        let host = url.host ?? ""
        guard host.contains("chatgpt.com") else { return }
        let path = url.path
        guard path == "/" || path.isEmpty || path.hasPrefix("/codex") || path.hasPrefix("/c/") else { return }
        finishLogin()
    }

    private func finishLogin() {
        guard !loginCompleted else { return }
        loginCompleted = true
        window.orderOut(nil)
        window.styleMask = [.borderless]
        Task { await refresh() }
    }

    func logout() {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let openAIRecords = records.filter { $0.displayName.contains("chatgpt.com") || $0.displayName.contains("openai.com") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: openAIRecords) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.usage = CodexUsage()
                    self.needsLogin = true
                }
            }
        }
    }

    // MARK: - Fetch via WKWebView JS (same-origin, uses real session)

    private var fetchNavDelegate: FetchNavDelegate?

    private func doFetch() async {
        let allCookies: [HTTPCookie] = await withCheckedContinuation { cont in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
        guard allCookies.contains(where: { $0.domain.contains("chatgpt.com") && !$0.value.isEmpty }) else {
            needsLogin = true
            return
        }

        if webView.url?.host?.contains("chatgpt.com") != true {
            await loadPage(URL(string: "https://chatgpt.com/codex")!)
        }

        await fetchDataViaJS()
    }

    private func loadPage(_ url: URL) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            let resume = {
                guard !resumed else { return }
                resumed = true
                cont.resume()
            }
            let del = FetchNavDelegate(resume)
            fetchNavDelegate = del
            webView.navigationDelegate = del
            webView.load(URLRequest(url: url))
            // Timeout — don't hang if page never loads
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { resume() }
        }
        webView.navigationDelegate = nil
        fetchNavDelegate = nil
    }

    private func fetchDataViaJS() async {
        do {
            // Step 1: get NextAuth session token + user info
            let sessionResult = try await webView.callAsyncJavaScript(
                "const r = await fetch('/api/auth/session'); return {s: r.status, b: await r.text()};",
                contentWorld: .page
            ) as? [String: Any]

            let sessionStatus = sessionResult?["s"] as? Int ?? 0
            let sessionBody   = sessionResult?["b"] as? String ?? ""

            if sessionStatus == 401 || sessionStatus == 403 {
                needsLogin = true
                return
            }

            needsLogin = false

            var authToken: String?
            var accountName: String?

            if sessionStatus == 200,
               let data = sessionBody.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                authToken = json["accessToken"] as? String
                    ?? json["access_token"] as? String
                    ?? json["token"] as? String
                if let user = json["user"] as? [String: Any] {
                    accountName = user["name"] as? String ?? user["email"] as? String
                }
            }

            // Step 2: fetch Codex usage with Bearer token
            let r = try await webView.callAsyncJavaScript("""
                const hdrs = token ? {'Authorization': 'Bearer ' + token} : {};
                const r = await fetch('/backend-api/codex/usage', {headers: hdrs});
                return {s: r.status, b: await r.text()};
            """, arguments: ["token": authToken ?? NSNull()],
                contentWorld: .page
            ) as? [String: Any]

            let s = r?["s"] as? Int ?? 0
            let b = r?["b"] as? String ?? ""

            if s == 200,
               let data = b.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parseUsage(json, accountName: accountName)
                return
            }

            usage = CodexUsage(lastUpdated: Date(), error: "codex/usage: HTTP \(s)", accountName: accountName)

        } catch {
            usage.error = "JS: \(error.localizedDescription)"
        }
    }

    // MARK: - Parsing

    private func parseUsage(_ json: [String: Any], accountName: String?) {
        var u = CodexUsage()
        u.lastUpdated = Date()
        u.accountName = accountName
        u.planType = json["plan_type"] as? String

        if let rateLimit = json["rate_limit"] as? [String: Any] {
            u.limitReached = rateLimit["limit_reached"] as? Bool ?? false
            if let primary = rateLimit["primary_window"] as? [String: Any] {
                if let pct = primary["used_percent"] as? Double {
                    u.usedPercent = pct
                } else if let pct = primary["used_percent"] as? Int {
                    u.usedPercent = Double(pct)
                }
            }
        }

        usage = u
    }

    // MARK: - Timer

    private func scheduleRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }
}

private class LoginWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(_ onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}

private class OpenAILoginDelegate: NSObject, WKNavigationDelegate {
    private let onURL: (URL) -> Void
    init(_ onURL: @escaping (URL) -> Void) { self.onURL = onURL }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        onURL(url)
    }
}

private class FetchNavDelegate: NSObject, WKNavigationDelegate {
    private let onDone: () -> Void
    init(_ onDone: @escaping () -> Void) { self.onDone = onDone }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onDone() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onDone() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onDone() }
}
