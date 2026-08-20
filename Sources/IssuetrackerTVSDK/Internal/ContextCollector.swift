import Foundation
import UIKit

// Gathers non-PII device + app metadata that's useful when triaging
// a bug report. Everything here is derivable from public APIs that
// don't require special entitlements. Deliberately avoids
// `UIDevice.current.name` and anything tied to the user's identity —
// that would turn the SDK into a privacy risk for integrators.
enum ContextCollector {
    @MainActor
    static func collect() -> [String: String] {
        let device = UIDevice.current
        let bundle = Bundle.main
        var out: [String: String] = [
            "platform": "tvOS",
            "osVersion": device.systemVersion,
            "locale": Locale.current.identifier,
            "timeZone": TimeZone.current.identifier,
        ]
        if let model = modelIdentifier() { out["deviceModel"] = model }
        if let bundleId = bundle.bundleIdentifier { out["appBundleId"] = bundleId }
        if let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            out["appVersion"] = version
        }
        if let build = bundle.infoDictionary?["CFBundleVersion"] as? String {
            out["appBuild"] = build
        }
        // On TV the rendered resolution matters for triage (1080p vs
        // 4K box, and the UI scale the app runs at).
        let screen = UIScreen.main
        out["screen"] = "\(Int(screen.bounds.width))x\(Int(screen.bounds.height))@\(Int(screen.scale))x"
        return out
    }

    /// Reads the hardware identifier — e.g. `AppleTV14,1` — via `uname(3)`.
    /// `UIDevice.model` only returns the generic family name ("Apple TV").
    private static func modelIdentifier() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return partial }
            return partial + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? nil : identifier
    }
}
