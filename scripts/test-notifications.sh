#!/bin/bash

# CryptoSage Push Notification Testing Script
# This script helps test the push notification flow end-to-end

set -e

PROJECT_ID="cryptosage-ai"
FUNCTIONS_REGION="us-central1"

echo "🔔 CryptoSage Push Notification Testing"
echo "========================================"
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Install it with:"
    echo "   npm install -g firebase-tools"
    exit 1
fi

# Check if logged in
if ! firebase projects:list &> /dev/null; then
    echo "❌ Not logged in to Firebase. Run:"
    echo "   firebase login"
    exit 1
fi

echo "✅ Firebase CLI ready"
echo ""

# Function to test Cloud Function deployment
test_function_deployment() {
    echo "📋 Testing Cloud Function Deployment"
    echo "======================================"

    functions=(
        "sendTestNotification"
        "sendPushNotification"
        "sendPriceAlertNotification"
        "sendPortfolioAlertNotification"
        "sendMarketAlertNotification"
    )

    for func in "${functions[@]}"; do
        if firebase functions:list | grep -q "$func"; then
            echo "✅ $func - DEPLOYED"
        else
            echo "❌ $func - NOT FOUND"
        fi
    done
    echo ""
}

# Function to check Firestore FCM tokens
check_fcm_tokens() {
    echo "📋 Checking FCM Tokens in Firestore"
    echo "===================================="
    echo ""
    echo "To check if your device registered an FCM token:"
    echo "1. Go to: https://console.firebase.google.com/project/$PROJECT_ID/firestore"
    echo "2. Navigate to: users/{your-user-id}/fcmTokens"
    echo "3. Look for a document with:"
    echo "   - token: (long string)"
    echo "   - platform: ios"
    echo "   - active: true"
    echo "   - lastUpdated: (recent timestamp)"
    echo ""
}

# Function to check APNs configuration
check_apns_config() {
    echo "📋 Checking APNs Configuration"
    echo "==============================="
    echo ""
    echo "Verify APNs is configured:"
    echo "1. Go to: https://console.firebase.google.com/project/$PROJECT_ID/settings/cloudmessaging"
    echo "2. Scroll to 'Apple app configuration'"
    echo "3. You should see either:"
    echo "   - APNs Authentication Key (.p8) uploaded"
    echo "   - OR APNs Certificate (.p12) uploaded"
    echo ""
    echo "If not configured, follow: APNS_SETUP_GUIDE.md"
    echo ""
}

# Function to check App Check
check_app_check() {
    echo "📋 Checking App Check Configuration"
    echo "===================================="
    echo ""
    echo "Verify App Check debug token:"
    echo "1. Go to: https://console.firebase.google.com/project/$PROJECT_ID/appcheck"
    echo "2. Click on your iOS app"
    echo "3. Check 'Manage debug tokens'"
    echo "4. You should see your debug token (valid for 7 days)"
    echo ""
    echo "To get a new debug token:"
    echo "1. Run the app in Xcode"
    echo "2. Check console for App Check debug token"
    echo "3. Register it in Firebase Console"
    echo ""
}

# Function to view logs
view_logs() {
    echo "📋 Viewing Recent Notification Logs"
    echo "===================================="
    echo ""

    read -p "Which function logs to view? (test/price/portfolio/market/all): " log_choice

    case $log_choice in
        test)
            firebase functions:log --only sendTestNotification --limit 20
            ;;
        price)
            firebase functions:log --only sendPriceAlertNotification --limit 20
            ;;
        portfolio)
            firebase functions:log --only sendPortfolioAlertNotification --limit 20
            ;;
        market)
            firebase functions:log --only sendMarketAlertNotification --limit 20
            ;;
        all)
            firebase functions:log | grep -i "notification\|push\|fcm" | tail -50
            ;;
        *)
            echo "Invalid choice. Use: test, price, portfolio, market, or all"
            ;;
    esac
    echo ""
}

# Function to test notification send
test_send_notification() {
    echo "📋 Send Test Notification"
    echo "=========================="
    echo ""
    echo "⚠️  This requires you to be authenticated as a test user in your iOS app."
    echo "⚠️  The function uses the authenticated user's ID to send the notification."
    echo ""
    echo "To test from iOS app instead, add this button to your Settings screen:"
    echo ""
    echo "Button(\"Send Test Notification\") {"
    echo "    Task {"
    echo "        let testNotif = functions.httpsCallable(\"sendTestNotification\")"
    echo "        try await testNotif.call()"
    echo "    }"
    echo "}"
    echo ""
}

# Main menu
show_menu() {
    echo "What would you like to test?"
    echo ""
    echo "1. Check Cloud Function Deployment"
    echo "2. Check APNs Configuration"
    echo "3. Check App Check Configuration"
    echo "4. Check FCM Tokens in Firestore"
    echo "5. View Notification Logs"
    echo "6. Send Test Notification Info"
    echo "7. Run All Checks"
    echo "8. Exit"
    echo ""
    read -p "Enter choice (1-8): " choice

    case $choice in
        1)
            test_function_deployment
            ;;
        2)
            check_apns_config
            ;;
        3)
            check_app_check
            ;;
        4)
            check_fcm_tokens
            ;;
        5)
            view_logs
            ;;
        6)
            test_send_notification
            ;;
        7)
            test_function_deployment
            check_apns_config
            check_app_check
            check_fcm_tokens
            ;;
        8)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter 1-8."
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
    clear
    show_menu
}

# Start
clear
show_menu
