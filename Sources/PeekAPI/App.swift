import SwiftUI
import AppKit
import PeekAPICore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu bar accessory without appearing in Dock
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

@main
struct PeekAPIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var engine = SpendEngine()

    var body: some Scene {
        MenuBarExtra {
            SpendMenuView(engine: engine)
                .onAppear {
                    engine.startPolling()
                }
        } label: {
            Text(engine.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}
