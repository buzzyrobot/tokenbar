import AppKit
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    var updaterController: SPUStandardUpdaterController!

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate(ignoringOtherApps: true)
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
