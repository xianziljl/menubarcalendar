import Foundation
import ServiceManagement

enum LoginItemManager {
    static var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }

        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static var requiresApproval: Bool {
        guard #available(macOS 13.0, *) else { return false }

        return SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LoginItemError.unsupportedSystem
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    enum LoginItemError: LocalizedError {
        case unsupportedSystem

        var errorDescription: String? {
            switch self {
            case .unsupportedSystem:
                return "Login items require macOS 13.0 or later."
            }
        }
    }
}
