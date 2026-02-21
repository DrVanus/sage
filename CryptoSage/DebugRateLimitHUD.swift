// Debug-only overlay HUD to show brief rate-limit/blocked indicators on screen.
#if DEBUG
import SwiftUI

struct DebugRateLimitHUD: View {
    @State private var lastHost: String = ""
    @State private var lastCode: Int = 0
    @State private var visible: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil
    @State private var notificationObserver: NSObjectProtocol? = nil

    private let maxVisible: TimeInterval = 5.0 // cap on-screen time regardless of TTL

    var body: some View {
        Group {
            if visible {
                HStack(spacing: 8) {
                    Image(systemName: "tortoise.fill").foregroundColor(.black)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rate-limited")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                        Text("\(lastHost) · code \(lastCode)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.black.opacity(0.8))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.yellow)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.black.opacity(0.25), lineWidth: 0.6)
                        )
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityHidden(true)
            }
        }
        .onAppear { subscribe() }
        .onDisappear { unsubscribe() }
    }

    private func subscribe() {
        notificationObserver = NotificationCenter.default.addObserver(forName: RateLimitDiagnostics.notification, object: nil, queue: .main) { [self] note in
            guard let userInfo = note.userInfo,
                  let host = userInfo["host"] as? String,
                  let code = userInfo["code"] as? Int,
                  let until = userInfo["until"] as? Date else { return }
            DispatchQueue.main.async {
                lastHost = host
                lastCode = code
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    visible = true
                }
                hideTask?.cancel()
                let ttl = max(1, until.timeIntervalSinceNow)
                let delay = min(maxVisible, ttl)
                hideTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    withAnimation(.easeInOut(duration: 0.2)) {
                        visible = false
                    }
                }
            }
        }
    }
    
    private func unsubscribe() {
        hideTask?.cancel()
        hideTask = nil
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
    }
}
#endif
