import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` (autostart, R50-R54) — no state of
/// its own. The OS-held registration is the only source of truth (same rule
/// as `Permissions.swift` for TCC: never shadow it in `AppConfig`).
public enum LoginItem {
    public static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// True when Gatekeeper is running this launch from an ephemeral
    /// App Translocation path (quarantined app opened without stripping
    /// `com.apple.quarantine` first, e.g. straight from a downloaded zip).
    /// `register()` would still succeed but bind the login item to this
    /// throwaway path, which stops existing at the next login — the entry
    /// looks enabled in Ajustes but silently never launches.
    public static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
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
