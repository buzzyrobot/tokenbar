import Foundation
import AppKit

struct TrackerTask: Identifiable, Codable {
    let id: UUID
    var name: String
    let startDate: Date
    var endDate: Date?

    var isRunning: Bool { endDate == nil }

    func formattedDuration(relativeTo now: Date = Date()) -> String {
        let d: TimeInterval
        if let end = endDate {
            d = end.timeIntervalSince(startDate)
        } else {
            d = now.timeIntervalSince(startDate)
        }
        let h = Int(d) / 3600
        let m = Int(d) % 3600 / 60
        let s = Int(d) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

class TaskStore: ObservableObject {
    static let shared = TaskStore()

    @Published var tasks: [TrackerTask] = [] {
        didSet { save() }
    }

    var activeTasks: [TrackerTask] { tasks.filter { $0.isRunning } }
    var completedTasks: [TrackerTask] { tasks.filter { !$0.isRunning } }

    private let saveKey = "tokenbar.tasks"

    private init() {
        load()
    }

    func startTask(name: String) {
        let task = TrackerTask(id: UUID(), name: name, startDate: Date())
        tasks.insert(task, at: 0)
    }

    @discardableResult
    func completeTask(id: UUID) -> TrackerTask? {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        tasks[index].endDate = Date()
        LogManager.shared.log(tasks[index])
        NSSound(named: "Glass")?.play()
        return tasks[index]
    }

    @discardableResult
    func completeTask(name: String) -> TrackerTask? {
        guard let index = tasks.firstIndex(where: { $0.name == name && $0.isRunning }) else { return nil }
        tasks[index].endDate = Date()
        LogManager.shared.log(tasks[index])
        NSSound(named: "Glass")?.play()
        return tasks[index]
    }

    func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
    }

    func clearCompleted() {
        tasks.removeAll { !$0.isRunning }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let saved = try? JSONDecoder().decode([TrackerTask].self, from: data) else { return }
        tasks = saved
    }
}
