import AppKit
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    static weak var current: AppDelegate?

    var updaterController: SPUStandardUpdaterController!

    private let feedURL = URL(string: "https://github.com/buzzyrobot/tokenbar/releases/latest/download/appcast.xml")!

    // MARK: - Update check

    func checkForUpdates() {
        URLSession.shared.dataTask(with: feedURL) { [weak self] data, _, error in
            DispatchQueue.main.async { self?.handleFeedResponse(data: data, error: error) }
        }.resume()
    }

    private func handleFeedResponse(data: Data?, error: Error?) {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        guard let data, let xml = String(data: data, encoding: .utf8),
              let latest = Self.parseVersion(from: xml) else {
            showAlert(title: "Błąd sprawdzania aktualizacji",
                      message: error?.localizedDescription ?? "Nie udało się odczytać kanału aktualizacji.")
            return
        }

        if latest.compare(current, options: .numeric) == .orderedDescending {
            let dmgURL = Self.parseDMGURL(from: xml)
            showUpdateAvailable(latest: latest, current: current, dmgURL: dmgURL)
        } else {
            showAlert(title: "Masz najnowszą wersję",
                      message: "TokenBar \(current) jest aktualny.")
        }
    }

    private static func parseVersion(from xml: String) -> String? {
        guard let start = xml.range(of: "<sparkle:shortVersionString>")?.upperBound,
              let end   = xml.range(of: "</sparkle:shortVersionString>")?.lowerBound,
              start <= end else { return nil }
        return String(xml[start..<end]).trimmingCharacters(in: .whitespaces)
    }

    private static func parseDMGURL(from xml: String) -> URL? {
        guard let start = xml.range(of: "enclosure url=\"")?.upperBound else { return nil }
        let suffix = xml[start...]
        guard let endIdx = suffix.range(of: "\"")?.lowerBound else { return nil }
        return URL(string: String(suffix[..<endIdx]))
    }

    // MARK: - Update install

    private func showUpdateAvailable(latest: String, current: String, dmgURL: URL?) {
        let alert = NSAlert()
        alert.messageText = "Dostępna aktualizacja \(latest)"
        alert.informativeText = "Zainstalowana wersja: \(current)\n\nAplikacja zostanie zaktualizowana i ponownie uruchomiona automatycznie."
        alert.addButton(withTitle: "Zainstaluj")
        alert.addButton(withTitle: "Nie teraz")

        if runModalFront(alert) == .alertFirstButtonReturn {
            if let dmgURL {
                downloadAndInstall(version: latest, dmgURL: dmgURL)
            }
        }
    }

    private func downloadAndInstall(version: String, dmgURL: URL) {
        let progressPanel = makeProgressPanel(message: "Pobieranie TokenBar \(version)…")
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        progressPanel.makeKeyAndOrderFront(nil)
        progressPanel.orderFrontRegardless()

        URLSession.shared.downloadTask(with: dmgURL) { [weak self] tempURL, _, error in
            DispatchQueue.main.async { progressPanel.close() }

            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.showAlert(title: "Błąd pobierania", message: error.localizedDescription)
                }
                return
            }
            guard let tempURL else { return }

            DispatchQueue.global(qos: .userInitiated).async {
                self.installFromDMG(at: tempURL, version: version)
            }
        }.resume()
    }

    private func installFromDMG(at tempURL: URL, version: String) {
        let dmgPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenBar-update.dmg")
        try? FileManager.default.removeItem(at: dmgPath)
        try? FileManager.default.moveItem(at: tempURL, to: dmgPath)

        // Mount DMG (volume is named "TokenBar")
        run("/usr/bin/hdiutil", "attach", dmgPath.path, "-nobrowse", "-quiet")

        let mountedApp = "/Volumes/TokenBar/TokenBar.app"
        let destination = "/Applications/TokenBar.app"

        // Copy .app to /Applications
        run("/bin/cp", "-Rf", mountedApp, destination)

        // Unmount
        run("/usr/bin/hdiutil", "detach", "/Volumes/TokenBar", "-quiet", "-force")

        // Clean up temp DMG
        try? FileManager.default.removeItem(at: dmgPath)

        // Launch new version and quit old
        DispatchQueue.main.async {
            self.run("/usr/bin/open", "-a", destination)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @discardableResult
    private func run(_ command: String, _ args: String...) -> Int32 {
        let p = Process()
        p.launchPath = command
        p.arguments = args
        p.launch()
        p.waitUntilExit()
        return p.terminationStatus
    }

    // MARK: - Alert helpers

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        runModalFront(alert)
    }

    @discardableResult
    private func runModalFront(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        NSApp.setActivationPolicy(.prohibited)
        return response
    }

    private func makeProgressPanel(message: String) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 76),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "TokenBar"
        panel.center()
        panel.isReleasedWhenClosed = false

        let label = NSTextField(labelWithString: message)
        label.frame = NSRect(x: 20, y: 42, width: 280, height: 18)
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)

        let bar = NSProgressIndicator()
        bar.frame = NSRect(x: 20, y: 18, width: 280, height: 14)
        bar.style = .bar
        bar.isIndeterminate = true
        bar.startAnimation(nil)

        panel.contentView?.addSubview(label)
        panel.contentView?.addSubview(bar)
        return panel
    }

    // MARK: - Sparkle delegate (automatic background checks)

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.windows.forEach { $0.orderFrontRegardless() }
        }
    }

    func standardUserDriverWillShowModalAlert() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.windows.forEach { $0.orderFrontRegardless() }
        }
    }

    // MARK: - Lifecycle

    private var lockFileDescriptor: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.current = self

        let lockPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.buzzyrobot.tokenbar.lock").path
        lockFileDescriptor = open(lockPath, O_CREAT | O_RDWR, 0o666)
        guard lockFileDescriptor >= 0,
              flock(lockFileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            NSApplication.shared.terminate(nil)
            return
        }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handleURL(url) }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "tokenbar",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let name = components.queryItems?.first(where: { $0.name == "name" })?.value ?? "Zadanie"
        let store = TaskStore.shared
        switch url.host {
        case "start":
            store.startTask(name: name)
        case "done":
            if let completed = store.completeTask(name: name) {
                NotificationManager.shared.notify(taskCompleted: completed)
            }
        default:
            break
        }
    }
}
