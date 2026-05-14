import Foundation
import WebKit
import AppKit

struct ClaudeUsage {
    var currentSessionPct: Double?
    var weeklyAllModelsPct: Double?
    var weeklyDesignPct: Double?
    var resetsAt: Date?
    var lastUpdated: Date?
    var error: String?
    var accountName: String?
}

@MainActor
class UsageFetcher: NSObject, ObservableObject {
    static let shared = UsageFetcher()

    @Published var usage = ClaudeUsage()
    @Published var isLoading = false
    @Published var needsLogin = false

    private var webView: WKWebView!
    private var window: NSWindow!
    private var refreshTimer: Timer?

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
    }

    // MARK: - Lifecycle

    private func startUp() async {
        await navigateToClaude()
        await doFetch()
        scheduleRefresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if webView.url?.host != "claude.ai" {
            await navigateToClaude()
        }
        await doFetch()
    }

    // MARK: - Login window

    func showLoginWindow() {
        if window.styleMask.contains(.titled) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        window.setFrame(.init(x: 0, y: 0, width: 960, height: 700), display: false)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "Claude.ai – zaloguj się"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let navDelegate = LoginDelegate { [weak self] url in
            self?.handlePostLoginURL(url)
        }
        let uiDelegate = LoginUIDelegate(
            onPopup: { [weak self] webView in self?.showPopup(webView) },
            onPopupClosed: { [weak self] in self?.finishLogin() }
        )
        setDelegate(navDelegate, uiDelegate: uiDelegate)
        webView.load(URLRequest(url: URL(string: "https://claude.ai")!))
    }

    private var popupWindow: NSWindow?
    private var loginCompleted = false

    private func handlePostLoginURL(_ url: URL) {
        guard url.host == "claude.ai",
              !url.path.hasPrefix("/login"),
              !url.path.hasPrefix("/signup") else { return }
        finishLogin()
    }

    private func finishLogin() {
        guard !loginCompleted else { return }
        loginCompleted = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.popupWindow?.orderOut(nil)
            self.popupWindow = nil
            self.hideLoginWindow()
            self.loginCompleted = false
            // Force fresh navigation so the auth session is fully active before fetch
            await self.navigateToClaude()
            await self.doFetch()
        }
    }

    private func showPopup(_ popupView: WKWebView) {
        let popupDelegate = PopupLoginDelegate { [weak self] url in
            self?.handlePostLoginURL(url)
        }
        let popupUIDelegate = PopupUIDelegate { [weak self] in
            self?.finishLogin()
        }
        popupView.navigationDelegate = popupDelegate
        popupView.uiDelegate = popupUIDelegate
        objc_setAssociatedObject(popupView, &AssocKeyPopupDelegate, popupDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(popupView, &AssocKeyUIDelegate, popupUIDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let win = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.title = "Logowanie"
        win.contentView = popupView
        win.center()
        win.makeKeyAndOrderFront(nil)
        popupWindow = win
    }

    func closeLoginWindow() {
        window.orderOut(nil)
        window.styleMask = [.borderless]
        window.setFrame(.init(x: -50000, y: -50000, width: 960, height: 700), display: false)
        Task { await refresh() }
    }

    func logout() {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let claudeRecords = records.filter { $0.displayName.contains("claude.ai") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: claudeRecords) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.usage = ClaudeUsage()
                    self.needsLogin = true
                }
            }
        }
    }

    private func hideLoginWindow() {
        window.orderOut(nil)
        window.styleMask = [.borderless]
        window.setFrame(.init(x: -50000, y: -50000, width: 960, height: 700), display: false)
    }

    // MARK: - Navigation helpers

    private func navigateToClaude() async {
        await withCheckedContinuation { [weak self] (cont: CheckedContinuation<Void, Never>) in
            guard let self else { cont.resume(); return }
            let delegate = FinishDelegate { cont.resume() }
            setDelegate(delegate)
            webView.load(URLRequest(url: URL(string: "https://claude.ai")!))
        }
    }

    private func setDelegate(_ delegate: (NSObject & WKNavigationDelegate), uiDelegate: (NSObject & WKUIDelegate)? = nil) {
        webView.navigationDelegate = delegate
        webView.uiDelegate = uiDelegate
        objc_setAssociatedObject(webView!, &AssocKeyDelegate, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if let uiDelegate {
            objc_setAssociatedObject(webView!, &AssocKeyUIDelegate, uiDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    // MARK: - API via WebKit JS (bypasses Cloudflare — runs inside the browser engine)

    private func doFetch() async {
        // callAsyncJavaScript wraps this body in async function() {} automatically
        let js = """
        try {
            const [r1, rAcc] = await Promise.all([
                fetch('/api/organizations', { headers: { 'Accept': 'application/json' } }),
                fetch('/api/account', { headers: { 'Accept': 'application/json' } })
            ]);
            if (!r1.ok) return { error: 'orgs_http_' + r1.status };
            const orgs = await r1.json();
            const orgId = orgs?.[0]?.uuid;
            if (!orgId) return { error: 'no_org_id', sample: JSON.stringify(orgs).slice(0,200) };

            let accountName = null;
            if (rAcc.ok) {
                const acc = await rAcc.json();
                accountName = acc?.full_name || acc?.name || acc?.email || null;
            }

            for (const ep of [
                '/api/organizations/' + orgId + '/rate_limit_status',
                '/api/organizations/' + orgId + '/usage',
                '/api/organizations/' + orgId + '/claude_usage',
            ]) {
                const r2 = await fetch(ep, { headers: { 'Accept': 'application/json' } });
                if (r2.ok) return { ok: true, ep, data: await r2.json(), accountName };
            }
            return { error: 'no_usage_endpoint', orgId };
        } catch (e) {
            return { error: 'exception_' + e.message };
        }
        """

        do {
            let result: Any? = try await withCheckedThrowingContinuation { cont in
                webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { res in
                    switch res {
                    case .success(let v): cont.resume(returning: v)
                    case .failure(let e): cont.resume(throwing: e)
                    }
                }
            }
            handleResult(result)
        } catch {
            usage.error = "WebKit: \(error.localizedDescription)"
        }
    }

    private func handleResult(_ raw: Any?) {
        guard let dict = raw as? [String: Any] else {
            needsLogin = true
            usage.error = "Wymagane logowanie"
            return
        }

        if let err = dict["error"] as? String {
            let isAuth = err.contains("_401") || err.contains("_403") || err.contains("no_org")
            needsLogin = isAuth
            usage.error = isAuth ? "Wymagane logowanie" : err
            return
        }

        guard let data = dict["data"] as? [String: Any] else { return }
        needsLogin = false
        let accountName = dict["accountName"] as? String
        parseUsage(data, accountName: accountName)
    }

    // MARK: - Parsing
    // API response shape (from /api/organizations/{id}/usage):
    // five_hour:           { utilization: Int, resets_at: String } — current session
    // seven_day:           { utilization: Int, resets_at: String } — weekly all models
    // seven_day_omelette:  { utilization: Int, resets_at: String } — weekly Claude Design

    private func parseUsage(_ json: [String: Any], accountName: String?) {
        var u = ClaudeUsage()
        u.lastUpdated = Date()
        u.accountName = accountName

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()

        func parseDate(_ s: String) -> Date? {
            iso.date(from: s) ?? isoBasic.date(from: s)
        }

        if let block = json["five_hour"] as? [String: Any] {
            u.currentSessionPct = utilization(block)
            if let s = block["resets_at"] as? String { u.resetsAt = parseDate(s) }
        }

        if let block = json["seven_day"] as? [String: Any] {
            u.weeklyAllModelsPct = utilization(block)
        }

        if let block = json["seven_day_omelette"] as? [String: Any] {
            u.weeklyDesignPct = utilization(block)
        }

        usage = u
    }

    private func utilization(_ dict: [String: Any]) -> Double? {
        if let v = dict["utilization"] as? Int { return Double(v) }
        if let v = dict["utilization"] as? Double { return v }
        return nil
    }

    // MARK: - Timer

    private func scheduleRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }
}

private var AssocKeyDelegate: UInt8 = 0
private var AssocKeyUIDelegate: UInt8 = 0
private var AssocKeyPopupDelegate: UInt8 = 0

private class FinishDelegate: NSObject, WKNavigationDelegate {
    private let onDone: () -> Void
    private var fired = false
    init(_ onDone: @escaping () -> Void) { self.onDone = onDone }
    private func done() { guard !fired else { return }; fired = true; onDone() }
    func webView(_ wv: WKWebView, didFinish _: WKNavigation!) { done() }
    func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError _: Error) { done() }
    func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) { done() }
}

private class LoginDelegate: NSObject, WKNavigationDelegate {
    private let onNavigated: (URL) -> Void
    init(_ onNavigated: @escaping (URL) -> Void) { self.onNavigated = onNavigated }
    func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
        if let url = wv.url { onNavigated(url) }
    }
}

private class PopupUIDelegate: NSObject, WKUIDelegate {
    private let onClose: () -> Void
    init(_ onClose: @escaping () -> Void) { self.onClose = onClose }
    func webViewDidClose(_ webView: WKWebView) { onClose() }
}

private class PopupLoginDelegate: NSObject, WKNavigationDelegate {
    private let onNavigated: (URL) -> Void
    init(_ onNavigated: @escaping (URL) -> Void) { self.onNavigated = onNavigated }
    func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
        if let url = wv.url { onNavigated(url) }
    }
}

private class LoginUIDelegate: NSObject, WKUIDelegate {
    private let onPopup: (WKWebView) -> Void
    private let onPopupClosed: () -> Void

    init(onPopup: @escaping (WKWebView) -> Void, onPopupClosed: @escaping () -> Void) {
        self.onPopup = onPopup
        self.onPopupClosed = onPopupClosed
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: .init(x: 0, y: 0, width: 500, height: 600), configuration: configuration)
        onPopup(popup)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        onPopupClosed()
    }
}
