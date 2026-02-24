# APNs Certificate Setup for CryptoSage Push Notifications

## ✅ What's Already Done
- ✅ PushNotificationManager.swift implemented
- ✅ AppCheckManager.swift implemented
- ✅ Firebase Cloud Functions deployed:
  - `sendTestNotification` - Test notification delivery
  - `sendPushNotification` - Generic notification sender
  - `sendPriceAlertNotification` - Price alert notifications
  - `sendPortfolioAlertNotification` - Portfolio change notifications
  - `sendMarketAlertNotification` - Market-wide alerts

## 📋 Step 1: Get Your APNs Authentication Key from Apple

### Option A: APNs Authentication Key (Recommended - Easier)

1. **Log in to Apple Developer Portal**
   - Go to: https://developer.apple.com/account/
   - Navigate to: **Certificates, Identifiers & Profiles** → **Keys**

2. **Create a New Key**
   - Click the **"+"** button
   - Give it a name: "CryptoSage Push Notifications"
   - Check the box for **"Apple Push Notifications service (APNs)"**
   - Click **"Continue"** → **"Register"**

3. **Download the Key**
   - ⚠️ **IMPORTANT**: You can only download this ONCE! Save it securely
   - Download the `.p8` file (e.g., `AuthKey_ABC123XYZ.p8`)
   - Note down:
     - **Key ID**: (shown on the download page, e.g., `ABC123XYZ`)
     - **Team ID**: (in the top-right corner of Apple Developer portal, e.g., `DEF456ABC`)

### Option B: APNs Certificate (Legacy)

If you prefer the certificate approach:

1. **Create Certificate Signing Request (CSR)**
   - Open **Keychain Access** on macOS
   - Go to: Keychain Access → Certificate Assistant → Request a Certificate from a Certificate Authority
   - Enter your email address
   - Select "Saved to disk"
   - Save the `CertificateSigningRequest.certSigningRequest` file

2. **Create APNs Certificate in Apple Developer Portal**
   - Go to: https://developer.apple.com/account/
   - Navigate to: **Certificates, Identifiers & Profiles** → **Certificates**
   - Click **"+"** button
   - Select: **Apple Push Notification service SSL (Sandbox & Production)**
   - Choose your App ID: `com.dee.CryptoSage`
   - Upload the CSR file you created
   - Download the certificate (`.cer` file)

3. **Convert Certificate to .p12**
   - Double-click the downloaded `.cer` file to add it to Keychain
   - Open **Keychain Access** → **My Certificates**
   - Find "Apple Push Services: com.dee.CryptoSage"
   - Right-click → Export
   - Save as `.p12` file with a password (remember this!)

## 📋 Step 2: Upload APNs to Firebase Console

### For APNs Authentication Key (.p8 file) - RECOMMENDED

1. **Open Firebase Console**
   - Go to: https://console.firebase.google.com/project/cryptosage-ai/overview
   - Click on the **⚙️ (Settings)** icon → **Project settings**

2. **Navigate to Cloud Messaging**
   - Click on the **"Cloud Messaging"** tab
   - Scroll down to the **"Apple app configuration"** section

3. **Upload APNs Key**
   - Under **"APNs Authentication Key"**, click **"Upload"**
   - Upload your `.p8` file
   - Enter the **Key ID** (from Apple Developer portal)
   - Enter the **Team ID** (from Apple Developer portal)
   - Click **"Upload"**

### For APNs Certificate (.p12 file) - LEGACY

1. **Open Firebase Console**
   - Go to: https://console.firebase.google.com/project/cryptosage-ai/overview
   - Click on the **⚙️ (Settings)** icon → **Project settings**

2. **Navigate to Cloud Messaging**
   - Click on the **"Cloud Messaging"** tab
   - Scroll down to the **"Apple app configuration"** section

3. **Upload APNs Certificate**
   - Under **"APNs Certificates"**, click **"Upload"**
   - Select **"Production"** (or "Development" for testing)
   - Upload your `.p12` file
   - Enter the password you set when exporting
   - Click **"Upload"**

## 📋 Step 3: Configure App Check Debug Token (For Testing)

1. **Run the iOS app in Debug mode**
   - Build and run CryptoSage in Xcode
   - Check the Xcode console for a line like:
   ```
   🔐 [App Check] Look for debug token in console and register it in Firebase Console
   ```
   - Copy the App Check debug token (it will be printed once)

2. **Register Debug Token in Firebase**
   - Go to: https://console.firebase.google.com/project/cryptosage-ai/appcheck
   - Click on your iOS app
   - Scroll down to **"Manage debug tokens"**
   - Click **"Add debug token"**
   - Paste the token from Xcode console
   - Give it a name: "CryptoSage Debug Token"
   - Click **"Save"**
   - ⚠️ Debug tokens are valid for **7 days**

## 📋 Step 4: Test the Notification Flow

### Test 1: FCM Token Registration

1. **Launch the app** on a physical iOS device (push notifications don't work in Simulator)
2. **Sign in** to the app
3. **Grant notification permissions** when prompted
4. **Check Firestore** to verify the token was saved:
   - Go to: https://console.firebase.google.com/project/cryptosage-ai/firestore
   - Navigate to: `users/{userId}/fcmTokens`
   - You should see a document with:
     - `token`: (FCM token string)
     - `platform`: "ios"
     - `active`: true
     - `lastUpdated`: (timestamp)

### Test 2: Send Test Notification

#### Option A: From iOS App (Add this to your Settings screen)

```swift
// Add a test button to your Settings or Debug screen
Button("Send Test Notification") {
    Task {
        do {
            let testNotif = functions.httpsCallable("sendTestNotification")
            let result = try await testNotif.call()
            print("✅ Test notification sent: \(result)")
        } catch {
            print("❌ Error: \(error)")
        }
    }
}
```

#### Option B: From Firebase Console

1. Go to: https://console.firebase.google.com/project/cryptosage-ai/firestore
2. Find your user document: `users/{userId}`
3. Copy your `userId`
4. Go to: https://console.firebase.google.com/project/cryptosage-ai/functions
5. Click on `sendTestNotification` → **"Testing"** tab
6. The function doesn't need parameters (it uses authenticated user)
7. Click **"Run the function"**

#### Option C: Using Firebase CLI

```bash
cd "/Users/danielmuskin/Desktop/CryptoSage main/firebase"

# Test notification (requires authentication)
firebase functions:call sendTestNotification --data '{}'
```

### Test 3: Deep Link Navigation

1. **Receive a test notification** (it includes deep link data)
2. **Tap the notification** when the app is in background
3. **Verify** the app navigates to the Portfolio screen
4. **Check Xcode console** for navigation logs

### Test 4: Price Alert Notification

From iOS app:
```swift
let priceAlert = functions.httpsCallable("sendPriceAlertNotification")
try await priceAlert.call([
    "userId": Auth.auth().currentUser!.uid,
    "symbol": "BTC",
    "currentPrice": 95000,
    "targetPrice": 94000,
    "isAbove": true,
    "changePercent": 5.2
])
```

## 🔧 Troubleshooting

### Issue: No FCM token received
**Solutions:**
- Ensure you're testing on a **physical device** (not Simulator)
- Check notification permissions: Settings → CryptoSage → Notifications
- Verify `PushNotificationManager.registerForPushNotifications()` is called after Firebase initialization
- Check Xcode console for error messages

### Issue: Token saved but notifications not received
**Solutions:**
- Verify APNs certificate/key is uploaded correctly in Firebase Console
- Check if App Check debug token is valid (7-day expiration)
- Ensure the device has internet connectivity
- Check Firebase Cloud Functions logs for errors
- Verify the app is properly signed with the correct provisioning profile

### Issue: App Check errors
**Solutions:**
- Register a new App Check debug token (they expire after 7 days)
- For production, switch to App Attest in `AppCheckManager.swift`
- Check Firebase console for App Check status

### Issue: Notifications work in development but not production
**Solutions:**
- Ensure you uploaded the **Production** APNs certificate (not Development)
- Switch App Check from Debug to App Attest for production
- Verify the production provisioning profile is configured correctly

## 📊 Monitoring

### View Cloud Function Logs
```bash
cd "/Users/danielmuskin/Desktop/CryptoSage main/firebase"
firebase functions:log --only sendTestNotification
```

### View All Notification-Related Logs
```bash
firebase functions:log | grep -i "notification\|push\|fcm"
```

### Check Firestore for FCM Tokens
- Go to: https://console.firebase.google.com/project/cryptosage-ai/firestore
- Path: `users/{userId}/fcmTokens`
- Verify `active: true` and recent `lastUpdated` timestamp

## 🚀 Next Steps After Testing

1. **Enable App Attest for Production**
   - In Xcode: Target → Signing & Capabilities → Add "App Attest"
   - The app already switches to App Attest automatically in Release builds

2. **Set Up Price Alert Monitoring**
   - The Cloud Functions are ready to receive price alerts
   - Implement price monitoring logic in your app or backend

3. **Configure Portfolio Alerts**
   - Call `sendPortfolioAlertNotification` when portfolio changes exceed user thresholds

4. **Set Up Market Alerts**
   - Use `evaluateMarketAlerts` scheduled function for automatic market monitoring
   - Or call `sendMarketAlertNotification` manually for breaking news

## 📝 Summary of Available Cloud Functions

| Function | Purpose | Usage |
|----------|---------|-------|
| `sendTestNotification` | Test notification delivery | No parameters needed |
| `sendPushNotification` | Send generic notification | Custom title, body, data |
| `sendPriceAlertNotification` | Price threshold alerts | Symbol, prices, change % |
| `sendPortfolioAlertNotification` | Portfolio value alerts | Value, change, top movers |
| `sendMarketAlertNotification` | Market-wide alerts | Title, body, severity |

All functions are callable from iOS using Firebase Functions:
```swift
let function = functions.httpsCallable("functionName")
let result = try await function.call(parameters)
```

---

**Need help?** Check the implementation files:
- Swift: `/CryptoSage/PushNotificationManager.swift`
- Cloud Functions: `/firebase/functions/src/index.ts` (lines 9365-9775)
- App Check: `/CryptoSage/AppCheckManager.swift`
