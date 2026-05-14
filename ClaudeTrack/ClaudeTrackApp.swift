import SwiftUI
import AppKit
import CoreText

@main
struct ClaudeTrackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = TaskStore.shared
    @StateObject private var fetcher = UsageFetcher.shared
    @StateObject private var codexFetcher = CodexFetcher.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(fetcher)
                .environmentObject(codexFetcher)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        NotificationManager.shared.requestPermission()
        registerFonts()
    }

    private func registerFonts() {
        for name in ["BitcountSingle-Regular", "BitcountSingle-Bold", "BitcountSingle-Light"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
                print("Font not found in bundle: \(name)")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        HStack(spacing: 2) {
            Image("TaskIconActive")
                .renderingMode(.template)
            if !store.activeTasks.isEmpty {
                Text("\(store.activeTasks.count)")
                    .font(.system(size: 11, weight: .medium))
            }
        }
    }
}
