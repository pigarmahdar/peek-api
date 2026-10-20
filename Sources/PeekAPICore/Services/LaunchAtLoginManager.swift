import Foundation
import ServiceManagement
import Combine

public protocol LaunchServiceProtocol {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

extension SMAppService: LaunchServiceProtocol {
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    @Published public var isEnabled: Bool = false
    @Published public var status: SMAppService.Status = .notRegistered
    @Published public var errorMessage: String? = nil

    private let service: LaunchServiceProtocol

    public init(service: LaunchServiceProtocol = SMAppService.mainApp) {
        self.service = service
        refreshStatus()
    }

    public func refreshStatus() {
        status = service.status
        isEnabled = (status == .enabled)
    }

    public func setLaunchAtLogin(_ enable: Bool) {
        errorMessage = nil
        do {
            if enable {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshStatus()
    }

    public func openSystemSettings() {
        service.openSystemSettings()
    }

    public static func statusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "enabled (will launch automatically at login)"
        case .notRegistered:
            return "not registered (manual launch only)"
        case .requiresApproval:
            return "requires approval (disabled in macOS System Settings > General > Login Items)"
        case .notFound:
            return "not found"
        @unknown default:
            return "unknown"
        }
    }

    /// Handles CLI commands and flags. Returns `true` if an action was handled and the process should exit.
    @MainActor
    @discardableResult
    public static func handleCommandLineArgs(_ args: [String], manager: LaunchAtLoginManager? = nil) -> Bool {
        let activeManager = manager ?? .shared
        let cleanArgs = Array(args.dropFirst())
        guard !cleanArgs.isEmpty else { return false }

        // Strip leading "api" if invoked as `peek api ...`
        let normalized: [String]
        if cleanArgs.first == "api" {
            normalized = Array(cleanArgs.dropFirst())
        } else {
            normalized = cleanArgs
        }

        if normalized.isEmpty {
            // e.g. `peek api` -> start app
            return false
        }

        let cmd = normalized.joined(separator: " ").lowercased()

        if cmd == "help" || cmd == "--help" || cmd == "-h" {
            printHelp()
            return true
        }

        if cmd == "login on" || cmd == "login enable" || cmd == "--enable-launch-at-login" {
            activeManager.setLaunchAtLogin(true)
            if let error = activeManager.errorMessage {
                print("❌ Failed to enable launch at login: \(error)")
            } else {
                print("✅ Enabled launch at login for peek-api.")
                print("   Status: \(statusDescription(activeManager.status))")
            }
            return true
        }

        if cmd == "login off" || cmd == "login disable" || cmd == "--disable-launch-at-login" {
            activeManager.setLaunchAtLogin(false)
            if let error = activeManager.errorMessage {
                print("❌ Failed to disable launch at login: \(error)")
            } else {
                print("✅ Disabled launch at login for peek-api.")
                print("   Status: \(statusDescription(activeManager.status))")
            }
            return true
        }

        if cmd == "login status" || cmd == "login" || cmd == "--status-launch-at-login" {
            activeManager.refreshStatus()
            print("⚡ peek-api launch at login status: \(statusDescription(activeManager.status))")
            return true
        }

        return false
    }

    private static func printHelp() {
        print("""
        peek-api ⚡ macOS Menu Bar AI Inference Monitor

        Usage:
          peek api                     Launch menu bar app
          peek api login status        Check launch at login status
          peek api login on            Enable launch at login
          peek api login off           Disable launch at login

        Options:
          --enable-launch-at-login     Enable launch at login
          --disable-launch-at-login    Disable launch at login
          --status-launch-at-login     Check launch at login status
          --help, -h                   Show this help message
        """)
    }
}
