import SwiftUI
import AppKit

// MARK: - Design tokens

private enum DS {
    static let bg      = Color.black
    static let surface = Color(red: 0x21/255.0, green: 0x21/255.0, blue: 0x21/255.0)
    static let label   = Color(red: 0x8b/255.0, green: 0x8b/255.0, blue: 0x8b/255.0)
    static let green   = Color(red: 0x3f/255.0, green: 0xcc/255.0, blue: 0x22/255.0)
    static let orange  = Color(red: 0xf8/255.0, green: 0x89/255.0, blue: 0x15/255.0)

    static let windowWidth: CGFloat = 253
    static let segmentCount: Int    = 27
    static let segmentW: CGFloat    = 6
    static let segmentSpacing: CGFloat = 2

    static func compactMedium(_ size: CGFloat) -> Font {
        Font(NSFont(name: ".SFCompactText-Medium", size: size)
             ?? NSFont.systemFont(ofSize: size, weight: .medium))
    }

    static func compactBold(_ size: CGFloat) -> Font {
        Font(NSFont(name: ".SFCompactText-Bold", size: size)
             ?? NSFont.boldSystemFont(ofSize: size))
    }
}

// MARK: - Root

struct MenuBarView: View {
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var fetcher: UsageFetcher
    @EnvironmentObject var codexFetcher: CodexFetcher
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if !store.activeTasks.isEmpty {
                ForEach(store.activeTasks) { task in
                    ActiveTaskRow(task: task).environmentObject(store)
                }
                RowDivider()
            }

            ClaudeSection(topPadding: store.activeTasks.isEmpty ? 16 : 0)
                .environmentObject(fetcher)

            if codexFetcher.isInitialized && !codexFetcher.needsLogin {
                CodexSection().environmentObject(codexFetcher)
                RowDivider()
            }

            if showSettings {
                SettingsPanel()
                    .environmentObject(fetcher)
                    .environmentObject(codexFetcher)
                RowDivider()
            }

            FooterBar(showSettings: $showSettings)
        }
        .background {
            Color.black.opacity(0.85)
                .background(.thinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(width: DS.windowWidth)
        .background(WindowConfigurator())
    }
}

// MARK: - Footer

struct FooterBar: View {
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("1.04 by buzzyrobot")
                .font(.system(size: 11))
                .foregroundStyle(DS.label.opacity(0.7))
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showSettings.toggle() }
            } label: {
                Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
                    .foregroundStyle(showSettings ? Color.white : DS.label)
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Settings panel

struct SettingsPanel: View {
    @EnvironmentObject var fetcher: UsageFetcher
    @EnvironmentObject var codexFetcher: CodexFetcher

    var body: some View {
        VStack(spacing: 0) {
            if codexFetcher.needsLogin {
                settingsRow(icon: "arrow.right.circle", label: "Zaloguj się do ChatGPT") { codexFetcher.showLoginWindow() }
            } else {
                settingsRow(icon: "person.slash", label: "Wyloguj z ChatGPT") { codexFetcher.logout() }
            }
            if !fetcher.needsLogin {
                settingsRow(icon: "person.slash", label: "Wyloguj z Claude.ai") { fetcher.logout() }
            }
            settingsRow(icon: "arrow.down.circle", label: "Sprawdź aktualizacje") {
                if let d = NSApp.delegate as? AppDelegate { d.checkForUpdates() }
            }
            settingsRow(icon: "power", label: "Zamknij TokenBar") { NSApplication.shared.terminate(nil) }
        }
        .padding(.vertical, 4)
    }

    private func settingsRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Active task row

struct ActiveTaskRow: View {
    let task: TrackerTask
    @EnvironmentObject var store: TaskStore
    @State private var frameIndex = 0

    private let frames = ["TaskIcon1", "TaskIcon2", "TaskIcon3"]

    var body: some View {
        TimelineView(.periodic(from: task.startDate, by: 1)) { context in
            HStack(spacing: 8) {
                Image(frames[frameIndex])
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.white)

                Text("Myślę...")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.label)
                    .lineLimit(1)

                Spacer()

                Text(task.formattedDuration(relativeTo: context.date))
                    .font(.custom("BitcountSingle-Regular", size: 15))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Button {
                    store.completeTask(id: task.id)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(DS.label)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("Zakończ zadanie")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .onReceive(Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()) { _ in
            frameIndex = (frameIndex + 1) % frames.count
        }
    }
}

// MARK: - Claude section

struct ClaudeSection: View {
    var topPadding: CGFloat = 16
    @EnvironmentObject var fetcher: UsageFetcher

    var body: some View {
        VStack(spacing: 0) {
            SectionTitle(text: "Claude", topPadding: topPadding)

            if fetcher.isLoading && fetcher.usage.currentSessionPct == nil {
                ProgressView().controlSize(.small).padding(16).frame(maxWidth: .infinity)
            } else if fetcher.needsLogin {
                loginRow(label: "Zaloguj się do Claude.ai") { fetcher.showLoginWindow() }
            } else if let err = fetcher.usage.error {
                errorLabel(err)
            } else {
                metricsView
            }

            Rectangle()
                .fill(Color(red: 0x21/255.0, green: 0x21/255.0, blue: 0x21/255.0))
                .frame(height: 1)
                .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private var metricsView: some View {
        if fetcher.usage.currentSessionPct == nil && fetcher.usage.weeklyAllModelsPct == nil {
            Text("Brak danych użycia")
                .font(.system(size: 12))
                .foregroundStyle(DS.label)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 4) {
                if let pct = fetcher.usage.currentSessionPct {
                    VStack(spacing: 0) {
                        MetricRow(label: "Bieżąca sesja", percent: pct)
                        if let resetsAt = fetcher.usage.resetsAt, resetsAt > Date() {
                            ResetRow(resetsAt: resetsAt, onExpire: { Task { await fetcher.refresh() } })
                        }
                    }
                }
                if let pct = fetcher.usage.weeklyAllModelsPct {
                    MetricRow(label: "Tygodniowo", percent: pct)
                }
                if let pct = fetcher.usage.weeklyDesignPct {
                    MetricRow(label: "Claude Design", percent: pct)
                }
            }
        }
    }

    private func errorLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(DS.label)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loginRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: "arrow.right.circle")
                .font(.system(size: 14)).foregroundStyle(Color.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Codex section

struct CodexSection: View {
    @EnvironmentObject var codexFetcher: CodexFetcher

    var body: some View {
        VStack(spacing: 0) {
            SectionTitle(text: "Codex", topPadding: 0)

            if codexFetcher.isLoading && codexFetcher.usage.usedPercent == nil {
                ProgressView().controlSize(.small).padding(16).frame(maxWidth: .infinity)
            } else if !codexFetcher.needsLogin, let err = codexFetcher.usage.error {
                Text(err).font(.system(size: 12)).foregroundStyle(DS.label)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            } else if let pct = codexFetcher.usage.usedPercent {
                MetricRow(
                    label: codexFetcher.usage.limitReached ? "Limit osiągnięty" : "Bieżąca sesja",
                    percent: pct
                )
            } else {
                Text("Brak danych").font(.system(size: 12)).foregroundStyle(DS.label)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

}

// MARK: - Metric row

struct MetricRow: View {
    let label: String
    let percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(DS.compactMedium(14))
                    .foregroundStyle(DS.label)
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .font(.custom("BitcountSingle-Light", size: 20))
                    .foregroundStyle(.white)
            }
            SegmentedBar(percent: percent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Reset row

struct ResetRow: View {
    let resetsAt: Date
    var onExpire: (() -> Void)? = nil
    private let sessionDuration: TimeInterval = 5 * 3600

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, resetsAt.timeIntervalSince(context.date))

            if remaining > 0 {
                let elapsed = sessionDuration - remaining
                let pct = min(100.0, elapsed / sessionDuration * 100)
                let h = Int(remaining) / 3600
                let m = Int(remaining) % 3600 / 60

                VStack(alignment: .leading, spacing: 5) {
                    ResetProgressBar(percent: pct)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Reset sesji")
                            .font(DS.compactMedium(14))
                            .foregroundStyle(DS.label)
                        Spacer()
                        Text(verbatim: h > 0
                            ? String(format: String(localized: "time_h_m"), h, m)
                            : String(format: String(localized: "time_m"), m))
                            .font(.custom("BitcountSingle-Regular", size: 12))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            } else {
                Color.clear.frame(height: 0)
                    .onAppear { onExpire?() }
            }
        }
    }
}

// MARK: - Segmented bar

struct SegmentedBar: View {
    let percent: Double
    var overrideColor: Color? = nil

    private var fillColor: Color { overrideColor ?? (percent >= 75 ? DS.orange : DS.green) }
    private var filledCount: Int { min(DS.segmentCount, max(0, Int((percent / 100.0 * Double(DS.segmentCount)).rounded()))) }

    var body: some View {
        GeometryReader { geo in
            let spacing = DS.segmentSpacing * CGFloat(DS.segmentCount - 1)
            let segW = max(1, (geo.size.width - spacing) / CGFloat(DS.segmentCount))
            HStack(spacing: DS.segmentSpacing) {
                ForEach(0..<DS.segmentCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i < filledCount ? fillColor : DS.surface)
                        .frame(width: segW, height: 15)
                }
            }
        }
        .frame(height: 15)
    }
}

// MARK: - Helpers

private struct SectionTitle: View {
    let text: String
    var topPadding: CGFloat = 16
    var body: some View {
        Text(text)
            .font(DS.compactBold(16))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, topPadding)
            .padding(.bottom, 6)
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.surface)
            .frame(height: 1)
            .padding(.vertical, 16)
    }
}

// Ciągły cienki pasek dla reset sesji (bez segmentów)
private struct ResetProgressBar: View {
    let percent: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(DS.surface)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white)
                    .frame(width: geo.size.width * CGFloat(min(percent / 100.0, 1.0)))
            }
        }
        .frame(height: 3)
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }
}

// MARK: - Window configurator

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.backgroundColor = .black
            window.isOpaque = true
            window.appearance = NSAppearance(named: .darkAqua)
            // Usuń border z NSThemeFrame
            if let frameView = window.contentView?.superview {
                frameView.wantsLayer = true
                frameView.layer?.masksToBounds = true
                frameView.layer?.cornerRadius = 10
                frameView.layer?.backgroundColor = NSColor.black.cgColor
                frameView.layer?.borderWidth = 0
                frameView.layer?.borderColor = NSColor.black.cgColor
            }
            // Usuń border z contentView
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.borderWidth = 0
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
