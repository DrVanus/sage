# CloudKit Community Accuracy Setup Guide

This guide explains how to set up CloudKit for the community accuracy learning system.

## Overview

The Community Accuracy System uses Apple's CloudKit to:
- Share anonymized prediction accuracy data across all users
- Aggregate community-wide statistics
- Enable collective learning from prediction outcomes

**Privacy Note**: Only aggregate statistics are shared. No personal data, portfolio information, or individual predictions are ever uploaded.

## Quick Setup Steps

### 1. Enable iCloud Capability in Xcode

1. Open the project in Xcode
2. Select the **CryptoSage** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **iCloud**
6. Check **CloudKit**
7. Xcode will create a default container: `iCloud.$(CFBundleIdentifier)`

### 2. Configure CloudKit Dashboard

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/)
2. Select your app's container
3. Go to **Schema** > **Record Types**
4. Create the following record types:

#### Record Type: `AccuracyContribution`

| Field Name | Type | Notes |
|------------|------|-------|
| `appVersion` | String | App version string |
| `timestamp` | Date/Time | When contributed |
| `evaluatedCount` | Int(64) | Total predictions evaluated |
| `directionsCorrect` | Int(64) | Correct direction predictions |
| `withinRangeCount` | Int(64) | Predictions within price range |
| `totalPriceError` | Double | Sum of price errors |
| `1h_total` | Int(64) | 1-hour timeframe total |
| `1h_correct` | Int(64) | 1-hour timeframe correct |
| `4h_total` | Int(64) | 4-hour timeframe total |
| `4h_correct` | Int(64) | 4-hour timeframe correct |
| `1d_total` | Int(64) | 24-hour timeframe total |
| `1d_correct` | Int(64) | 24-hour timeframe correct |
| `7d_total` | Int(64) | 7-day timeframe total |
| `7d_correct` | Int(64) | 7-day timeframe correct |
| `30d_total` | Int(64) | 30-day timeframe total |
| `30d_correct` | Int(64) | 30-day timeframe correct |
| `bullishTotal` | Int(64) | Total bullish predictions |
| `bullishCorrect` | Int(64) | Correct bullish predictions |
| `bearishTotal` | Int(64) | Total bearish predictions |
| `bearishCorrect` | Int(64) | Correct bearish predictions |
| `neutralTotal` | Int(64) | Total neutral predictions |
| `neutralCorrect` | Int(64) | Correct neutral predictions |

#### Record Type: `CommunityAggregate`

| Field Name | Type | Notes |
|------------|------|-------|
| `totalPredictions` | Int(64) | Total across all users |
| `contributorCount` | Int(64) | Number of contributors |
| `directionsCorrect` | Int(64) | Total correct directions |
| `withinRangeCount` | Int(64) | Total within range |
| `totalPriceError` | Double | Sum of all errors |
| `1h_total` | Int(64) | 1-hour aggregate total |
| `1h_correct` | Int(64) | 1-hour aggregate correct |
| `4h_total` | Int(64) | 4-hour aggregate total |
| `4h_correct` | Int(64) | 4-hour aggregate correct |
| `1d_total` | Int(64) | 24-hour aggregate total |
| `1d_correct` | Int(64) | 24-hour aggregate correct |
| `7d_total` | Int(64) | 7-day aggregate total |
| `7d_correct` | Int(64) | 7-day aggregate correct |
| `30d_total` | Int(64) | 30-day aggregate total |
| `30d_correct` | Int(64) | 30-day aggregate correct |
| `bullishTotal` | Int(64) | Aggregate bullish total |
| `bullishCorrect` | Int(64) | Aggregate bullish correct |
| `bearishTotal` | Int(64) | Aggregate bearish total |
| `bearishCorrect` | Int(64) | Aggregate bearish correct |
| `neutralTotal` | Int(64) | Aggregate neutral total |
| `neutralCorrect` | Int(64) | Aggregate neutral correct |

### 3. Set Up Security Roles

1. In CloudKit Dashboard, go to **Schema** > **Security Roles**
2. For `AccuracyContribution`:
   - **World**: Read, Create (users can read all and create their own)
   - **Authenticated**: Read, Write (users can update their own records)
3. For `CommunityAggregate`:
   - **World**: Read (everyone can read aggregates)
   - **Admin only**: Write (only backend can update)

### 4. Deploy Schema to Production

1. In CloudKit Dashboard, click **Deploy Schema to Production**
2. This makes the record types available in the production environment

## How It Works

### Data Flow

```
User makes predictions → Predictions evaluated locally →
User opts in → Anonymized stats uploaded to CloudKit →
App aggregates all contributions → Everyone sees community accuracy
```

### Fallback Behavior

The system has multiple fallback levels:

1. **Pre-computed Aggregate**: Best - uses `CommunityAggregate` record
2. **On-device Aggregation**: Good - aggregates from `AccuracyContribution` records
3. **Baseline Data**: Fallback - uses hardcoded realistic baseline metrics

This ensures users always see community data even if CloudKit isn't fully set up.

### Automatic Aggregation (Optional)

For better performance with many users, you can set up a CloudKit subscription + Cloud Function to automatically compute the `CommunityAggregate` record when contributions are added. This is optional - the app will do on-device aggregation if no pre-computed aggregate exists.

## Testing

### Development Environment

1. Use the **Development** environment in CloudKit Dashboard
2. Test with your development provisioning profile
3. Data is separate from production

### Verifying Setup

1. Run the app
2. Make some predictions and wait for them to expire
3. Enable "Help Improve Predictions" in the accuracy dashboard
4. Tap "Contribute Now"
5. Check CloudKit Dashboard for the new `AccuracyContribution` record

## Troubleshooting

### "iCloud is not available"
- User needs to sign in to iCloud on their device
- Check Settings > Apple ID > iCloud

### "Network error"
- Check internet connection
- CloudKit may be temporarily unavailable

### No community data showing
- Ensure CloudKit is properly configured
- Check that record types are deployed to production
- The app will fall back to baseline data if CloudKit fails

### Contributions not uploading
- Check that user has opted in
- User needs at least 5 evaluated predictions
- Check CloudKit Dashboard for errors

## Privacy

The system is designed with privacy in mind:

- **No personal data**: Only aggregate statistics are shared
- **Random IDs**: Contribution IDs are random UUIDs, not tied to Apple ID
- **Opt-in only**: Users must explicitly enable contribution
- **No tracking**: We don't track individual users across sessions
- **Transparent**: Users can see exactly what data is shared

## Files

- `CommunityAccuracyService.swift` - Main CloudKit service
- `PredictionAccuracyView.swift` - UI components for community accuracy
- `CSAI1.entitlements` - iCloud entitlements

## Support

If you encounter issues with CloudKit setup, check:
1. Apple Developer account status
2. CloudKit Dashboard for errors
3. Xcode console for detailed error messages
