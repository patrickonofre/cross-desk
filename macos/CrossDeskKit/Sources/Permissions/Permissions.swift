import AppKit

/// TCC onboarding helpers (R12). Grant checks live next to the APIs that need
/// them: `InputCapture.hasPermission()` (Input Monitoring, server) and
/// `InputInjector.hasPermission()` (Accessibility, client).
public enum Permissions {
    public static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
