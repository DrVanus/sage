# CryptoSage Backup & Sync Guide

## For Mac Studio (Cortana handles automatically)
- ✅ Creates backup tags when you approve changes
- ✅ Pushes to GitHub immediately after changes
- ✅ You can revert anytime with: `git reset --hard backup-YYYY-MM-DD`

## For MacBook Pro Setup (Run once)

### Step 1: Get the latest code
```bash
cd /path/to/your/CryptoSage/project
git pull origin main
```

### Step 2: Run the setup script
```bash
bash scripts/macbook-sync-setup.sh
```

### Step 3: Fix the paths
Edit these files with your actual paths:
- `~/sync-cryptosage.sh` - Update project path
- `~/Library/LaunchAgents/com.cryptosage.sync.plist` - Update username

### Step 4: Start auto-sync
```bash
launchctl load ~/Library/LaunchAgents/com.cryptosage.sync.plist
```

### Step 5: Test it works
```bash
~/sync-cryptosage.sh
```

## How it works
- **Mac Studio:** I push changes → GitHub
- **MacBook Pro:** Auto-pulls every 15 minutes from GitHub
- **You:** Always have latest code, can work on either machine
- **Backup:** Tagged snapshots you can revert to anytime

## Manual sync (if auto-sync not working)
**Before working:** `git pull origin main`
**After changes:** `git add -A && git commit -m "description" && git push origin main`