#!/bin/bash
# MacBook Pro sync setup - run this once on your MacBook Pro

echo "Setting up CryptoSage auto-sync on MacBook Pro..."

# 1. Create sync script
cat > ~/sync-cryptosage.sh << 'EOF'
#!/bin/bash
cd "/path/to/your/CryptoSage/project"  # UPDATE THIS PATH
echo "🔄 Syncing CryptoSage..."
git fetch origin
if [ $(git rev-list --count HEAD..origin/main) -gt 0 ]; then
    git pull origin main
    echo "✅ Updated with new changes"
else
    echo "✅ Already up to date"
fi
EOF

chmod +x ~/sync-cryptosage.sh

# 2. Create LaunchAgent for auto-sync every 15 minutes
cat > ~/Library/LaunchAgents/com.cryptosage.sync.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cryptosage.sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/YOURUSERNAME/sync-cryptosage.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit ~/sync-cryptosage.sh and fix the project path"
echo "2. Edit ~/Library/LaunchAgents/com.cryptosage.sync.plist and fix YOURUSERNAME"
echo "3. Run: launchctl load ~/Library/LaunchAgents/com.cryptosage.sync.plist"
echo "4. Test: ~/sync-cryptosage.sh"