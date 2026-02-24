//
//  NotificationTestView.swift
//  CryptoSage
//
//  Push Notification Testing View
//  Add this to your app's Settings or Debug menu for easy testing
//

import SwiftUI
import FirebaseFunctions
import FirebaseAuth

struct NotificationTestView: View {
    @StateObject private var pushManager = PushNotificationManager.shared
    @State private var testResult: String = ""
    @State private var isLoading = false

    let functions = Functions.functions()

    var body: some View {
        List {
            // Status Section
            Section("Push Notification Status") {
                StatusRow(title: "Push Enabled", value: pushManager.isPushEnabled ? "✅ Yes" : "❌ No")
                StatusRow(title: "Registered", value: pushManager.isRegistered ? "✅ Yes" : "❌ No")

                if let token = pushManager.fcmToken {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FCM Token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(token.prefix(40)) + "...")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                }
            }

            // Registration Section
            Section("Registration") {
                Button {
                    Task {
                        await pushManager.registerForPushNotifications()
                    }
                } label: {
                    Label("Request Push Permissions", systemImage: "bell.badge")
                }
                .disabled(pushManager.isPushEnabled)

                Button {
                    if let token = pushManager.fcmToken {
                        pushManager.uploadFCMTokenToFirestore(token)
                        testResult = "✅ Token uploaded to Firestore"
                    } else {
                        testResult = "❌ No FCM token available"
                    }
                } label: {
                    Label("Upload Token to Firestore", systemImage: "square.and.arrow.up")
                }
                .disabled(pushManager.fcmToken == nil)
            }

            // Testing Section
            Section("Send Test Notifications") {
                Button {
                    sendTestNotification()
                } label: {
                    Label("Send Test Notification", systemImage: "paperplane")
                }
                .disabled(!pushManager.isRegistered || isLoading)

                Button {
                    sendTestPriceAlert()
                } label: {
                    Label("Test Price Alert (BTC)", systemImage: "bitcoinsign.circle")
                }
                .disabled(!pushManager.isRegistered || isLoading)

                Button {
                    sendTestPortfolioAlert()
                } label: {
                    Label("Test Portfolio Alert", systemImage: "chart.line.uptrend.xyaxis")
                }
                .disabled(!pushManager.isRegistered || isLoading)
            }

            // Result Section
            if !testResult.isEmpty {
                Section("Result") {
                    Text(testResult)
                        .font(.caption)
                        .foregroundColor(testResult.contains("✅") ? .green : .red)
                }
            }

            // Deep Link Testing
            Section("Deep Link Testing") {
                Button {
                    testDeepLink(type: "priceAlert", symbol: "BTC")
                } label: {
                    Label("Test Coin Detail Navigation", systemImage: "link")
                }

                Button {
                    testDeepLink(type: "portfolioAlert")
                } label: {
                    Label("Test Portfolio Navigation", systemImage: "link")
                }
            }

            // Info Section
            Section("Info") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to Test:")
                        .font(.headline)

                    Text("1. Ensure push permissions are granted")
                    Text("2. Verify FCM token is registered")
                    Text("3. Send a test notification")
                    Text("4. Check if notification appears")
                    Text("5. Tap notification to test deep links")

                    Divider()

                    Text("Note: Notifications only work on physical devices, not in Simulator.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .font(.caption)
            }
        }
        .navigationTitle("Notification Testing")
        .toolbar {
            if isLoading {
                ProgressView()
            }
        }
    }

    // MARK: - Test Functions

    func sendTestNotification() {
        guard let _ = Auth.auth().currentUser else {
            testResult = "❌ Not authenticated"
            return
        }

        isLoading = true
        testResult = "Sending test notification..."

        Task {
            do {
                let testNotif = functions.httpsCallable("sendTestNotification")
                let result = try await testNotif.call()

                if let data = result.data as? [String: Any],
                   let sent = data["sent"] as? Int {
                    await MainActor.run {
                        testResult = "✅ Test notification sent to \(sent) device(s)"
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        testResult = "✅ Test notification sent"
                        isLoading = false
                    }
                }

                print("✅ Test notification result: \(result.data)")
            } catch {
                await MainActor.run {
                    testResult = "❌ Error: \(error.localizedDescription)"
                    isLoading = false
                }
                print("❌ Test notification error: \(error)")
            }
        }
    }

    func sendTestPriceAlert() {
        guard let userId = Auth.auth().currentUser?.uid else {
            testResult = "❌ Not authenticated"
            return
        }

        isLoading = true
        testResult = "Sending price alert..."

        Task {
            do {
                let priceAlert = functions.httpsCallable("sendPriceAlertNotification")
                let result = try await priceAlert.call([
                    "userId": userId,
                    "symbol": "BTC",
                    "currentPrice": 95000,
                    "targetPrice": 94000,
                    "isAbove": true,
                    "changePercent": 5.2
                ])

                await MainActor.run {
                    if let data = result.data as? [String: Any],
                       let sent = data["sent"] as? Int {
                        testResult = "✅ Price alert sent to \(sent) device(s)"
                    } else {
                        testResult = "✅ Price alert sent"
                    }
                    isLoading = false
                }

                print("✅ Price alert result: \(result.data)")
            } catch {
                await MainActor.run {
                    testResult = "❌ Error: \(error.localizedDescription)"
                    isLoading = false
                }
                print("❌ Price alert error: \(error)")
            }
        }
    }

    func sendTestPortfolioAlert() {
        guard let userId = Auth.auth().currentUser?.uid else {
            testResult = "❌ Not authenticated"
            return
        }

        isLoading = true
        testResult = "Sending portfolio alert..."

        Task {
            do {
                let portfolioAlert = functions.httpsCallable("sendPortfolioAlertNotification")
                let result = try await portfolioAlert.call([
                    "userId": userId,
                    "totalValue": 50000,
                    "changeAmount": 2500,
                    "changePercent": 5.5,
                    "topMovers": [
                        ["symbol": "BTC", "change": 8.2],
                        ["symbol": "ETH", "change": 6.1]
                    ]
                ])

                await MainActor.run {
                    if let data = result.data as? [String: Any],
                       let sent = data["sent"] as? Int {
                        testResult = "✅ Portfolio alert sent to \(sent) device(s)"
                    } else {
                        testResult = "✅ Portfolio alert sent"
                    }
                    isLoading = false
                }

                print("✅ Portfolio alert result: \(result.data)")
            } catch {
                await MainActor.run {
                    testResult = "❌ Error: \(error.localizedDescription)"
                    isLoading = false
                }
                print("❌ Portfolio alert error: \(error)")
            }
        }
    }

    func testDeepLink(type: String, symbol: String? = nil) {
        // Simulate receiving a notification with deep link data
        var userInfo: [AnyHashable: Any] = ["type": type]

        if let symbol = symbol {
            userInfo["symbol"] = symbol
        }

        pushManager.handleRemoteNotification(userInfo)
        testResult = "✅ Deep link posted: \(type)"
    }
}

struct StatusRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

struct NotificationTestView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NotificationTestView()
        }
    }
}
