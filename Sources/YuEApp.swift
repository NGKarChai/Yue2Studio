import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let icon = NSImage(named: "AppIcon") ??
            NSImage(contentsOfFile: Bundle.main.bundlePath + "/Contents/Resources/AppIcon.icns") ??
            NSImage(contentsOfFile: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Sources/Resources/AppIcon.png").path) {
            NSApp.applicationIconImage = icon
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct YuEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("YuE Studio - Native macOS Music Generation") {
            MainView(appState: appState)
                .frame(minWidth: 1080, idealWidth: 1200, minHeight: 720, idealHeight: 800)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Song") {
                    appState.songTitle = "Untitled Song"
                    appState.currentTab = .studio
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Generate Song") {
                    appState.startGeneration()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Demo Preview") {
                    appState.startDemoSynthesis()
                }
                .keyboardShortcut("d", modifiers: .command)
            }
        }
    }
}
