import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` (autostart, R50-R54) — no state of
/// its own. The OS-held registration is the only source of truth (same rule
/// as `Permissions.swift` for TCC: never shadow it in `AppConfig`).
public enum LoginItem {
    public static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    public static func register() throws {
        try SMAppService.mainApp.register()
    }

    public static func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    public static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
