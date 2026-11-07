import SwiftUI
import AppKit

@main
struct IELTSMockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("雅思模考", id: "main") {
            RootView()
                .environmentObject(app)
                .environmentObject(app.settings)
                .environmentObject(app.bank)
                .environmentObject(app.history)
                .environmentObject(app.ai)
                .environmentObject(app.models)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear { DebugDriver.installIfRequested(app) }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("考试") {
                Button("放大字号") { app.settings.fontScale = min(1.6, app.settings.fontScale + 0.1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("缩小字号") { app.settings.fontScale = max(0.8, app.settings.fontScale - 0.1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("恢复默认字号") { app.settings.fontScale = 1.0 }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("下一题") { app.session?.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                    .disabled(app.session == nil)
                Button("上一题") { app.session?.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                    .disabled(app.session == nil)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(app)
                .environmentObject(app.settings)
                .environmentObject(app.bank)
                .environmentObject(app.history)
                .environmentObject(app.ai)
                .environmentObject(app.models)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
