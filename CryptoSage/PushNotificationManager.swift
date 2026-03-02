//
//  PushNotificationManager.swift
//  CryptoSage
//
//  Manages Firebase Cloud Messaging (FCM) push notifications.
//  Handles token registration, notification delivery, and deep linking.
//

import Foundation
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import Combine

final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published var fcmToken: String?
    @Published var isPushEnabled: Bool = false
    @Published var isRegistered: Bool = false

    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        setupMessagingDelegate()
    }

    // MARK: - Setup

    func setupMessagingDelegate() {
        Messaging.messaging().delegate = self
    }

    // MARK: - Registration

    /// Request notification permissions and register for remote notifications
    func registerForPushNotifications() async {
        let center = UNUserNotificationCenter.current()

        do {
            // Request permission
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])

            await MainActor.run {
                self.isPushEnabled = granted
            }

            if granted {
                #if DEBUG
                print("✅ Push notification permission granted")
                #endif

                // Register for remote notifications on main thread
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                #if DEBUG
                print("❌ Push notification permission denied")
                #endif
            }
        } catch {
            #if DEBUG
            print("❌ Error requesting notification permission: \(error.localizedDescription)")
            #endif
        }
    }

    /// Called when device token is received from APNs
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        #if DEBUG
        print("📱 APNs Device Token: \(token)")
        #endif

        // Set APNs token for FCM
        Messaging.messaging().apnsToken = deviceToken
    }

    /// Called when device token registration fails
    func didFailToRegisterForRemoteNotifications(error: Error) {
        #if DEBUG
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
        #endif

        DispatchQueue.main.async {
            self.isRegistered = false
        }
    }

    // MARK: - FCM Token Management

    /// Upload FCM token to Firestore for the current user
    func uploadFCMTokenToFirestore(_ token: String) {
        guard let userId = Auth.auth().currentUser?.uid else {
            #if DEBUG
            print("⚠️ No authenticated user, skipping FCM token upload")
            #endif
            return
        }

        let tokenData: [String: Any] = [
            "token": token,
            "platform": "ios",
            "lastUpdated": FieldValue.serverTimestamp(),
            "active": true,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "deviceModel": UIDevice.current.model
        ]

        // Use token itself as document ID to prevent duplicates
        db.collection("users")
            .document(userId)
            .collection("fcmTokens")
            .document(token)
            .setData(tokenData, merge: true) { error in
                if let error = error {
                    #if DEBUG
                    print("❌ Error uploading FCM token: \(error.localizedDescription)")
                    #endif
                } else {
                    #if DEBUG
                    print("✅ FCM token uploaded to Firestore for user: \(userId)")
                    #endif
                    DispatchQueue.main.async {
                        self.isRegistered = true
                    }
                }
            }
    }

    /// Remove FCM token from Firestore (called on logout or token invalidation)
    func removeFCMTokenFromFirestore(_ token: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        db.collection("users")
            .document(userId)
            .collection("fcmTokens")
            .document(token)
            .updateData(["active": false]) { error in
                if let error = error {
                    #if DEBUG
                    print("❌ Error deactivating FCM token: \(error.localizedDescription)")
                    #endif
                } else {
                    #if DEBUG
                    print("✅ FCM token deactivated")
                    #endif
                }
            }
    }

    // MARK: - Notification Handling

    /// Handle incoming remote notification
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        #if DEBUG
        print("📬 Received remote notification: \(userInfo)")
        #endif

        // Extract notification type and data
        guard let notificationType = userInfo["type"] as? String else {
            #if DEBUG
            print("⚠️ No notification type found")
            #endif
            return
        }

        // Post navigation event based on notification type
        switch notificationType {
        case "priceAlert":
            if let symbol = userInfo["symbol"] as? String {
                NotificationCenter.default.post(
                    name: .navigateToCoinDetail,
                    object: nil,
                    userInfo: ["symbol": symbol]
                )
            }

        case "portfolioAlert":
            NotificationCenter.default.post(
                name: .navigateToPortfolio,
                object: nil
            )

        case "marketAlert":
            if let alertType = userInfo["alertType"] as? String {
                NotificationCenter.default.post(
                    name: .navigateToMarket,
                    object: nil,
                    userInfo: ["alertType": alertType]
                )
            }

        case "general":
            // Show in-app message or navigate to specific screen
            if let screen = userInfo["screen"] as? String {
                NotificationCenter.default.post(
                    name: .navigateToScreen,
                    object: nil,
                    userInfo: ["screen": screen]
                )
            }

        default:
            #if DEBUG
            print("⚠️ Unknown notification type: \(notificationType)")
            #endif
        }
    }
}

// MARK: - MessagingDelegate

extension PushNotificationManager: MessagingDelegate {
    /// Called when FCM registration token is received or refreshed
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        #if DEBUG
        print("🔑 FCM Registration Token: \(fcmToken ?? "nil")")
        #endif

        guard let token = fcmToken else { return }

        DispatchQueue.main.async {
            self.fcmToken = token
        }

        // Upload token to Firestore
        uploadFCMTokenToFirestore(token)

        // Post notification for observers
        NotificationCenter.default.post(
            name: .fcmTokenReceived,
            object: nil,
            userInfo: ["token": token]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let fcmTokenReceived = Notification.Name("fcmTokenReceived")
    static let navigateToCoinDetail = Notification.Name("navigateToCoinDetail")
    static let navigateToPortfolio = Notification.Name("navigateToPortfolio")
    static let navigateToMarket = Notification.Name("navigateToMarket")
    static let navigateToScreen = Notification.Name("navigateToScreen")
}
