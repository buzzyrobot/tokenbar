import AppKit
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    var updaterController: SPUStandardUpdaterController!

    // Called when Sparkle is about to show an update available window
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        bringSparkleToFront()
    }

    // Called when Sparkle is about to show any modal alert (including "you're up to date")
    func standardUserDriverWillShowModalAlert() {
        bringSparkleToFront()
    }

    private func bringSparkleToFront() {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        // Give Sparkle time to create its window, then force it above everything
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.windows.forEach { $0.orderFrontRegardless() }
        }
    }

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
