import AppKit
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    var updaterController: SPUStandardUpdaterController!

    private let feedURL = URL(string: "https://github.com/buzzyrobot/tokenbar/releases/latest/download/appcast.xml")!
    private let releasesURL = URL(string: "https://github.com/buzzyrobot/tokenbar/releases/latest")!

    // MARK: - Custom update check (reliable NSAlert-based, bypasses Sparkle UI)

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
            showUpdateAvailable(latest: latest, current: current)
        } else {
            showAlert(title: "Masz najnowszą wersję",
                      message: "TokenBar \(current) jest aktualny.")
        }
    }

    private static func parseVersion(from xml: String) -> String? {
        guard let start = xml.range(of: "<sparkle:shortVersionString>")?.upperBound,
              let end = xml.range(of: "</sparkle:shortVersionString>")?.lowerBound,
              start <= end else { return nil }
        return String(xml[start..<end]).trimmingCharacters(in: .whitespaces)
    }

    private func showUpdateAvailable(latest: String, current: String) {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        let alert = NSAlert()
        alert.messageText = "Dostępna aktualizacja \(latest)"
        alert.informativeText = "Zainstalowana wersja: \(current)"
        alert.addButton(withTitle: "Pobierz")
        alert.addButton(withTitle: "Nie teraz")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releasesURL)
        }
    }

    private func showAlert(title: String, message: String) {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: - Sparkle delegate (handles automatic background checks only)

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.windows.forEach { $0.orderFrontRegardless() }
        }
    }

    func standardUserDriverWillShowModalAlert() {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.windows.forEach { $0.orderFrontRegardless() }
        }
    }

    // MARK: - Lifecycle

    private var lockFileDescriptor: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
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
