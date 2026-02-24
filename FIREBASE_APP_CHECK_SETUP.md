# Firebase App Check Setup Guide

## Overview

Firebase App Check protects your Cloud Functions from abuse by ensuring requests come from your authentic iOS app and not from unauthorized clients, bots, or scrapers.

**Status**: ✅ Implemented (Enforcement: Disabled by default)

## Architecture

```
┌─────────────────────┐
│   iOS App           │
│   (CryptoSage)      │
│                     │
│  AppCheckManager    │
│    │                │
│    ├─ Debug Token   │ (Development)
│    └─ App Attest    │ (Production)
└─────────┬───────────┘
          │ App Check Token
          ↓
┌─────────────────────┐
│ Firebase App Check  │
│   Verification      │
└─────────┬───────────┘
          │ Verified Request
          ↓
┌─────────────────────┐
│  Cloud Functions    │
│  (45+ functions)    │
│                     │
│  • getMarketSentiment
│  • getCoinInsight   │
│  • getPricePrediction
│  • ... and more     │
└─────────────────────┘
```

## Components

### 1. iOS App (AppCheckManager.swift)

**Location**: `CryptoSage/AppCheckManager.swift`

**Features**:
- Debug provider for development (requires token registration)
- App Attest provider for production (iOS 14+)
- Device Check fallback (iOS 11-13)
- Token verification and debugging utilities

**Configuration**:
- ✅ Imports: `FirebaseAppCheck` added to CryptoSageAIApp.swift
- ✅ Initialization: Configured before `FirebaseApp.configure()`
- ✅ Verification: Debug verification in DEBUG builds

### 2. Cloud Functions (index.ts)

**Location**: `firebase/functions/src/index.ts`

**Configuration**:
```typescript
const ENFORCE_APP_CHECK = process.env.ENABLE_APP_CHECK === "true" ||
                          (process.env.NODE_ENV === "production" &&
                           process.env.ENABLE_APP_CHECK !== "false");

setGlobalOptions({
  maxInstances: 10,
  region: "us-central1",
  enforceAppCheck: ENFORCE_APP_CHECK,
});
```

**Protected Functions**: All 45+ Cloud Functions including:
- AI Functions: `getMarketSentiment`, `getCoinInsight`, `getPricePrediction`
- Market Data: `getCoinGeckoMarkets`, `getBinance24hrTickers`
- Trading: `getTradingSignal`, `getOrderBookDepth`
- Chat: `sendChatMessage`, `consultDeepSeek`
- Privacy: `exportUserData`, `deleteUserData`

## Setup Instructions

### Phase 1: Development Setup (Testing)

#### Step 1: Run the iOS App

1. Build and run the app in Xcode (Debug configuration)
2. Check the console output for the App Check debug token:
   ```
   🔐 [App Check] Configured with DEBUG provider
   🔐 [App Check] Look for debug token in console and register it in Firebase Console
   [Firebase/AppCheck][I-FAA001001] Firebase App Check Debug Token: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
   ```
3. Copy the debug token (starts with the UUID format)

#### Step 2: Register Debug Token in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **cryptosage-ai**
3. Navigate to: **Project Settings > App Check**
4. Click **"Apps"** tab
5. Find your iOS app: **com.dee.CryptoSage**
6. Click **"Manage debug tokens"**
7. Click **"Add debug token"**
8. Paste the token from Step 1
9. Add a description: "Development - [Your Name] - [Device]"
10. Click **"Add"**

**Note**: Debug tokens expire after 7 days. You'll need to repeat this process.

#### Step 3: Test Without Enforcement (Recommended First)

Test that App Check tokens are being generated without enforcing them:

```bash
# In the firebase/functions directory
cd firebase/functions

# Verify current config
firebase functions:config:get

# App Check is disabled by default, so functions should work
# Test your app - Cloud Functions should work normally
```

The app will generate and send App Check tokens, but Cloud Functions won't reject requests without valid tokens yet.

#### Step 4: Enable App Check Enforcement (When Ready)

Once you've verified tokens are working:

```bash
cd firebase/functions

# Set the environment variable to enable App Check
firebase functions:config:set \
    app_check.enabled=true \
    runtime.node_env=production

# Deploy the functions
npm run build
firebase deploy --only functions

# Or use the convenience script
cd ..
./enable-app-check.sh production
```

**⚠️ WARNING**: After enabling enforcement, requests without valid App Check tokens will be rejected with a 403 error.

### Phase 2: Production Setup (App Store)

#### Step 1: Enable App Attest in Xcode

1. Open CryptoSage.xcodeproj in Xcode
2. Select the **CryptoSage** target
3. Go to **Signing & Capabilities**
4. Click **"+ Capability"**
5. Add **"App Attest"**
6. Ensure your provisioning profile supports App Attest

#### Step 2: Register App in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **cryptosage-ai**
3. Navigate to: **Project Settings > App Check**
4. Click **"Apps"** tab
5. Find your iOS app: **com.dee.CryptoSage**
6. Under **"App Attest"**, click **"Register"**
7. Confirm registration

**Note**: App Attest works automatically on iOS 14+ devices. Older devices (iOS 11-13) will fall back to Device Check.

#### Step 3: Enable Enforcement in Production

The Cloud Functions are already configured to respect the `ENABLE_APP_CHECK` environment variable:

```bash
# Enable App Check for production
firebase functions:config:set app_check.enabled=true

# Deploy to production
firebase deploy --only functions --project cryptosage-ai
```

## Testing & Verification

### Test 1: Verify Token Generation (iOS)

Add this to any view controller or SwiftUI view:

```swift
import SwiftUI

struct AppCheckTestView: View {
    @State private var tokenStatus: String = "Testing..."

    var body: some View {
        VStack(spacing: 20) {
            Text("App Check Test")
                .font(.title)

            Text(tokenStatus)
                .foregroundColor(.secondary)

            Button("Verify App Check") {
                AppCheckManager.shared.verifySetup { success in
                    tokenStatus = success ? "✅ Token OK" : "❌ Token Failed"
                }
            }

            Button("Refresh Token") {
                AppCheckManager.shared.refreshToken { success, error in
                    if let error = error {
                        tokenStatus = "❌ Error: \(error.localizedDescription)"
                    } else {
                        tokenStatus = success ? "✅ Token Refreshed" : "❌ Refresh Failed"
                    }
                }
            }
        }
        .padding()
    }
}
```

### Test 2: Verify Cloud Function Enforcement

```bash
# Test with curl (should fail if enforcement is enabled)
curl -X POST \
  https://us-central1-cryptosage-ai.cloudfunctions.net/getMarketSentiment \
  -H "Content-Type: application/json" \
  -d '{"data": {}}'

# Expected response with enforcement:
# HTTP 403 Forbidden
# {"error": "Unauthenticated"}

# Expected response without enforcement:
# HTTP 200 OK
# {"result": {...}}
```

### Test 3: Monitor Logs

```bash
# View Cloud Functions logs
firebase functions:log --project cryptosage-ai

# Look for App Check entries:
# ✅ Success: Request processed normally
# ❌ Failure: "App Check verification failed" or "Unauthenticated"
```

## Troubleshooting

### Problem: iOS app shows "Token Failed"

**Solutions**:
1. Check that debug token is registered in Firebase Console
2. Verify token hasn't expired (7 days for debug tokens)
3. Check console for specific error messages
4. Try refreshing the token with `AppCheckManager.shared.refreshToken()`

### Problem: Cloud Functions return 403 errors

**Solutions**:
1. Verify App Check is configured in iOS app
2. Check that debug token is registered (development)
3. Verify App Attest is registered (production)
4. Temporarily disable enforcement to test:
   ```bash
   firebase functions:config:unset app_check.enabled
   firebase deploy --only functions
   ```

### Problem: "App Check debug token not found" in console

**Solutions**:
1. Run the app once to generate a token
2. Look for the token in Xcode console output (search for "Debug Token")
3. The token appears on first launch after App Check is configured
4. Copy the entire UUID string and register it in Firebase Console

### Problem: Production app fails after App Store release

**Solutions**:
1. Verify App Attest capability is enabled in Xcode
2. Check that App Attest is registered in Firebase Console
3. Ensure your App Store provisioning profile supports App Attest
4. Test with TestFlight first before releasing to App Store

## Environment Variables

### Firebase Functions Config

```bash
# View current configuration
firebase functions:config:get

# Set App Check enabled
firebase functions:config:set app_check.enabled=true

# Set environment (production/development)
firebase functions:config:set runtime.node_env=production

# Disable App Check (for testing)
firebase functions:config:unset app_check.enabled

# View specific config
firebase functions:config:get app_check
```

## Deployment Checklist

### Pre-Deployment
- [ ] iOS app has `FirebaseAppCheck` imported
- [ ] `AppCheckManager.swift` is included in target
- [ ] App Check is configured in `CryptoSageAIApp.swift`
- [ ] Debug token is registered in Firebase Console
- [ ] Test app can generate tokens successfully

### Development Deployment
- [ ] Test without enforcement first
- [ ] Verify all Cloud Functions work
- [ ] Check logs for App Check token generation
- [ ] Enable enforcement gradually

### Production Deployment
- [ ] App Attest capability enabled in Xcode
- [ ] App Attest registered in Firebase Console
- [ ] Test with TestFlight
- [ ] Monitor Cloud Functions logs
- [ ] Enable enforcement with `enable-app-check.sh`

## Security Best Practices

1. **Debug Tokens**:
   - Only use in development
   - Rotate tokens regularly (they expire in 7 days)
   - Never commit tokens to version control

2. **App Attest**:
   - Always enable for production builds
   - Test thoroughly with TestFlight before App Store release
   - Monitor Firebase Console for unusual patterns

3. **Monitoring**:
   - Check Firebase Console > App Check for usage metrics
   - Monitor Cloud Functions logs for failed verification attempts
   - Set up alerts for high failure rates

4. **Rate Limiting**:
   - App Check works alongside existing rate limiting
   - Consider implementing per-user rate limits in addition to App Check
   - Monitor usage patterns in Firebase Console

## Cost Impact

**App Check Pricing**:
- First 10,000 verifications per month: **Free**
- Additional verifications: **$0.001 per verification**

**Estimated Monthly Cost for CryptoSage**:
- Active users: ~1,000
- Avg requests per user: ~100/day
- Monthly verifications: ~3,000,000
- Estimated cost: **$2,990/month** at full scale

**Note**: Start with development/debug tokens (free) and monitor usage before enabling for all users.

## Quick Reference

### Enable App Check
```bash
cd firebase
./enable-app-check.sh production
```

### Disable App Check
```bash
firebase functions:config:unset app_check.enabled
firebase deploy --only functions
```

### Register Debug Token
1. Run app in Xcode
2. Copy token from console
3. Firebase Console > Project Settings > App Check > Manage debug tokens
4. Add token

### View Logs
```bash
firebase functions:log --limit 50
```

### Test Token Generation
```swift
AppCheckManager.shared.verifySetup { success in
    print(success ? "✅ OK" : "❌ Failed")
}
```

## Support

For issues or questions:
1. Check Firebase Console > App Check for diagnostics
2. View Cloud Functions logs: `firebase functions:log`
3. Review iOS console output for App Check messages
4. Consult [Firebase App Check Documentation](https://firebase.google.com/docs/app-check)

---

**Last Updated**: 2024-02-24
**Status**: ✅ Implemented, ⚠️ Enforcement Disabled (Enable when ready)
**Next Steps**: Test with debug tokens, then enable enforcement in production
