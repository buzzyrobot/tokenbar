import Foundation

struct SessionLog: Codable {
    let id: UUID
    let name: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
}

class LogManager {
    static let shared = LogManager()
    let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.buzzyrobot.tokenbar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("sessions.json")
    }

    func log(_ task: TrackerTask) {
        guard let endDate = task.endDate else { return }
        let entry = SessionLog(
            id: task.id,
            name: task.name,
            startDate: task.startDate,
            endDate: endDate,
            duration: endDate.timeIntervalSince(task.startDate)
        )
        var all = loadAll()
        all.append(entry)
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: fileURL)
        }
    }

    func loadAll() -> [SessionLog] {
        guard let data = try? Data(contentsOf: fileURL),
              let sessions = try? JSONDecoder().decode([SessionLog].self, from: data) else {
            return []
        }
        return sessions
    }

    func todayStats() -> (count: Int, total: TimeInterval, avg: TimeInterval) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todaySessions = loadAll().filter {
            calendar.startOfDay(for: $0.endDate) == today
        }
        let total = todaySessions.reduce(0.0) { $0 + $1.duration }
        let avg = todaySessions.isEmpty ? 0 : total / Double(todaySessions.count)
        return (todaySessions.count, total, avg)
    }
}
