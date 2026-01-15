import Foundation

/// Toggleable logging utility for the news/article pipeline.
/// Enable by setting `UserDefaults.standard.bool(forKey: "NewsDebug.Logging") = true` in a debug build, or flip at runtime.
enum NewsDebug {
    /// Global flag. Defaults to true in DEBUG builds, false otherwise, but can be overridden by UserDefaults.
    static var enabled: Bool {
        #if DEBUG
        return UserDefaults.standard.object(forKey: "NewsDebug.Logging") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "NewsDebug.Logging")
        #else
        return UserDefaults.standard.bool(forKey: "NewsDebug.Logging")
        #endif
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
