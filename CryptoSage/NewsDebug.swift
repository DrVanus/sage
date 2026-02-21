import Foundation

/// Toggleable logging utility for the news/article pipeline.
/// Enable by setting `UserDefaults.standard.bool(forKey: "NewsDebug.Logging") = true` in a debug build, or flip at runtime.
enum NewsDebug {
    /// Global flag. Defaults to false to reduce console noise. Enable via UserDefaults if needed.
    static var enabled: Bool {
        return UserDefaults.standard.bool(forKey: "NewsDebug.Logging")
    }

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print("[News] \(message())")
    }

    static func warn(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print("[News][WARN] \(message())")
    }

    static func error(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print("[News][ERROR] \(message())")
    }
}
