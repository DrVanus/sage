# App Store Privacy Nutrition Labels

This document provides the exact values to enter in App Store Connect when submitting CryptoSage for review.

## Overview

Apple requires all apps to declare what data they collect through "Privacy Nutrition Labels" in App Store Connect. This information is displayed to users on the App Store before they download your app.

## How to Fill Out Privacy Labels

1. Go to App Store Connect > Your App > App Privacy
2. Click "Get Started" or "Edit" under Data Types
3. Follow the sections below

---

## Data Types to Declare

### 1. Identifiers

**Select:** Device ID

**Usage Purpose:** Analytics

**Linked to User:** No (anonymous analytics only)

**Tracking:** No

**Explanation:** We collect anonymous device identifiers for crash reporting and analytics. These are not linked to user identity.

---

### 2. Usage Data

**Select:** Product Interaction

**Usage Purpose:** Analytics, App Functionality

**Linked to User:** No

**Tracking:** No

**Explanation:** We collect anonymous usage data such as:
- Which screens users view
- Which features are used
- Session duration
- Button taps and interactions

This helps us improve the app.

---

### 3. Diagnostics

**Select:** Crash Data, Performance Data

**Usage Purpose:** App Functionality

**Linked to User:** No

**Tracking:** No

**Explanation:** We collect crash reports and performance metrics (load times, API response times) to fix bugs and improve stability.

---

### 4. Financial Info (if applicable)

**Select:** Payment Info (only if you use in-app purchases)

**Usage Purpose:** App Functionality

**Linked to User:** Yes (handled by Apple)

**Tracking:** No

**Explanation:** Payment processing is handled entirely by Apple's App Store. We do not store payment information.

---

## Data NOT Collected

Explicitly confirm you do NOT collect:

- [ ] Contact Info (name, email, phone)
- [ ] Health & Fitness
- [ ] Location (precise or coarse)
- [ ] Contacts
- [ ] User Content (photos, videos, audio)
- [ ] Browsing History
- [ ] Search History (we don't log user searches)
- [ ] Sensitive Info
- [ ] Other Data Types not listed above

---

## Summary Table for App Store Connect

| Data Type | Collected | Purpose | Linked to User | Used for Tracking |
|-----------|-----------|---------|----------------|-------------------|
| Device ID | Yes | Analytics | No | No |
| Product Interaction | Yes | Analytics, Functionality | No | No |
| Crash Data | Yes | Functionality | No | No |
| Performance Data | Yes | Functionality | No | No |
| Payment Info | Yes* | Functionality | Yes (Apple) | No |

*Only if using StoreKit for subscriptions

---

## Important Notes

### "Tracking" Definition
Apple defines "tracking" as linking user data with third-party data for advertising or sharing with data brokers. 

**CryptoSage does NOT track users.** Our analytics are:
- Anonymous (no user IDs linked to data)
- First-party only (no data sharing with advertisers)
- Not used for cross-app tracking

### Third-Party SDKs

If you add TelemetryDeck or Sentry as described in the implementation:

**TelemetryDeck:**
- Privacy-first analytics
- No personal data collection
- GDPR compliant by design
- No additional privacy labels needed beyond "Product Interaction"

**Sentry:**
- Crash and error reporting
- Requires declaring "Crash Data" and "Performance Data"
- Does not track users
- Does not collect PII

### OpenAI Integration

The app sends user prompts to OpenAI's API for AI chat functionality. This is covered under "App Functionality" but you should note:

- User prompts are sent to OpenAI's servers
- This is disclosed in the Privacy Policy
- No additional privacy label needed (considered "User Content" only if stored)

---

## Hosting the Privacy Policy

Apple requires a **publicly accessible URL** for your privacy policy. We've created web-ready files in the `/docs` folder:

- `docs/index.html` - Landing page with links
- `docs/privacy-policy.html` - Full privacy policy
- `docs/terms.html` - Terms of service

### Option 1: GitHub Pages (Free, Recommended)

1. Push your repo to GitHub
2. Go to repo Settings > Pages
3. Set Source to "Deploy from a branch" > `main` > `/docs`
4. Your URL will be: `https://yourusername.github.io/repo-name/privacy-policy.html`

### Option 2: Netlify (Free)

1. Create account at netlify.com
2. Drag the `/docs` folder to deploy
3. Custom domain available for free

### Option 3: Your Own Domain

1. Upload the `/docs` folder contents to your web server
2. Access at: `https://cryptosage.ai/privacy-policy.html`

### App Store Connect Setup

1. Go to App Store Connect > Your App > App Information
2. Under "Privacy Policy URL", enter your hosted URL
3. Example: `https://cryptosage.ai/privacy-policy.html`

---

## Before Submission Checklist

- [ ] Privacy Policy URL is set in App Store Connect
- [ ] Privacy Policy URL is publicly accessible (test in incognito browser)
- [ ] Privacy Policy is accessible from within the app
- [ ] Analytics opt-out toggle works (Settings > Privacy)
- [ ] All data types above are declared
- [ ] "Data Used to Track You" is set to NONE
- [ ] Review that all declarations match actual app behavior
- [ ] Terms of Service URL is set (optional but recommended)

---

## Contact

If Apple requests clarification during review, refer them to:
- In-app Privacy Policy (Settings > Privacy Policy)
- In-app Analytics Info (Settings > Privacy & Analytics > What We Collect)
- Email: privacy@cryptosage.ai
