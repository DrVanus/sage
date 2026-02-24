#!/bin/bash
# CryptoSage Build Verification Script
# Run after any code changes to catch issues BEFORE they reach GitHub.
# Usage: bash scripts/verify-build.sh [--quick|--full]
#
# --quick: Just check imports and build (default)
# --full:  Also check for duplicate types, missing switch cases, etc.

set -euo pipefail

PROJECT_DIR="/Users/danielmuskin/Desktop/CryptoSage main"
XCODEPROJ="$PROJECT_DIR/CryptoSage.xcodeproj"
PBXPROJ="$XCODEPROJ/project.pbxproj"
XCODEBUILD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
SOURCE_DIR="$PROJECT_DIR/CryptoSage"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
MODE="${1:---quick}"

echo "🔍 CryptoSage Build Verification"
echo "================================="
echo ""

# ─────────────────────────────────────────────
# CHECK 1: Import → SPM Dependency Verification
# ─────────────────────────────────────────────
echo "📦 Check 1: Verifying all imports have SPM dependencies..."

# Known system/built-in frameworks (don't need SPM)
# System/platform frameworks that ship with iOS/macOS — no SPM needed
# Also includes compiler-internal modules (prefixed with _)
SYSTEM_MODULES="Foundation|UIKit|SwiftUI|Combine|CryptoKit|Security|WebKit|SafariServices|StoreKit|CoreData|CoreImage|CoreGraphics|QuartzCore|AVFoundation|Photos|PhotosUI|MapKit|CoreLocation|UserNotifications|BackgroundTasks|WidgetKit|AppIntents|Charts|os|Darwin|Swift|Network|AuthenticationServices|LocalAuthentication|Observation|AppKit|CloudKit|CommonCrypto|CoreBluetooth|EventKit|ImageIO|MetalKit|Metal|UniformTypeIdentifiers|CoreHaptics|GameplayKit|SpriteKit|SceneKit|CoreMotion|CoreTelephony|SystemConfiguration|CoreText|CoreFoundation|Accelerate|IOKit|MobileCoreServices|MediaPlayer|MessageUI|MultipeerConnectivity|NaturalLanguage|PencilKit|PDFKit|RealityKit|ReplayKit|Vision|VisionKit|CoreML|CreateML|_Concurrency|_StringProcessing"

# Firebase submodules that are implicitly linked through the main Firebase products
FIREBASE_IMPLICIT="FirebaseCore|FirebaseCoreInternal|FirebaseInstallations|FirebaseCoreDiagnostics|FirebaseSessions"

# Extract all unique imports from Swift files
IMPORTS=$(grep -rh "^import " "$SOURCE_DIR" --include="*.swift" 2>/dev/null | sort -u | sed 's/import //' | sed 's/@testable //' | tr -d ' ')

for MODULE in $IMPORTS; do
    # Skip system modules
    if echo "$MODULE" | grep -qE "^($SYSTEM_MODULES)$"; then
        continue
    fi

    # Skip Firebase submodules that are implicitly linked
    if echo "$MODULE" | grep -qE "^($FIREBASE_IMPLICIT)$"; then
        continue
    fi

    # Skip submodule imports (e.g., "struct FirebaseCore.Options")
    if echo "$MODULE" | grep -qE "\."; then
        continue
    fi

    # Skip compiler-internal modules (prefixed with _)
    if echo "$MODULE" | grep -qE "^_"; then
        continue
    fi

    # Check if this module is in the pbxproj
    if ! grep -q "productName = $MODULE" "$PBXPROJ" 2>/dev/null; then
        echo -e "  ${RED}❌ MISSING DEP: 'import $MODULE' found in code but NOT linked in Xcode project${NC}"
        # Find which files use it
        grep -rl "^import $MODULE" "$SOURCE_DIR" --include="*.swift" 2>/dev/null | while read -r f; do
            echo -e "     → $(basename "$f")"
        done
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo -e "  ${GREEN}✅ All imports have matching SPM dependencies${NC}"
fi
echo ""

# ─────────────────────────────────────────────
# CHECK 2: Duplicate Type Definitions
# ─────────────────────────────────────────────
echo "🔄 Check 2: Checking for duplicate type definitions..."

# Types that MUST only be defined in TradingTypes.swift
# Check for TOP-LEVEL duplicates of canonical types only
# (Nested enums inside structs/classes are fine — they're scoped)
CANONICAL_TYPES=("^public enum OrderType" "^public enum TradeSide" "^public enum TradingError")
CANONICAL_LABELS=("enum OrderType" "enum TradeSide" "enum TradingError")

for i in "${!CANONICAL_TYPES[@]}"; do
    PATTERN="${CANONICAL_TYPES[$i]}"
    LABEL="${CANONICAL_LABELS[$i]}"
    COUNT=$(grep -rl "$PATTERN" "$SOURCE_DIR" --include="*.swift" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 1 ]; then
        echo -e "  ${RED}❌ DUPLICATE: '$LABEL' defined at top-level in $COUNT files (should be only in TradingTypes.swift):${NC}"
        grep -rl "$PATTERN" "$SOURCE_DIR" --include="*.swift" 2>/dev/null | while read -r f; do
            echo -e "     → $(basename "$f")"
        done
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "  ${GREEN}✅ No duplicate type definitions found${NC}"
fi
echo ""

# ─────────────────────────────────────────────
# CHECK 3: Uncommitted Changes Check
# ─────────────────────────────────────────────
echo "📝 Check 3: Checking git status..."
cd "$PROJECT_DIR"
GIT_STATUS=$(git status --porcelain 2>/dev/null || true)
UNCOMMITTED=$(echo "$GIT_STATUS" | grep -v "^??" | grep -c "." || true)
UNTRACKED=$(echo "$GIT_STATUS" | grep "^??" | grep -c "\.swift$" || true)

if [ "$UNCOMMITTED" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠️  $UNCOMMITTED uncommitted changes${NC}"
    WARNINGS=$((WARNINGS + 1))
fi
if [ "$UNTRACKED" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠️  $UNTRACKED untracked .swift files (may need to be committed)${NC}"
    git status --porcelain 2>/dev/null | grep "^??" | grep "\.swift$" | while read -r line; do
        echo -e "     → ${line#\?\? }"
    done
    WARNINGS=$((WARNINGS + 1))
fi
if [ "$UNCOMMITTED" -eq 0 ] && [ "$UNTRACKED" -eq 0 ]; then
    echo -e "  ${GREEN}✅ Working tree clean${NC}"
fi
echo ""

# ─────────────────────────────────────────────
# CHECK 4: Build
# ─────────────────────────────────────────────
echo "🔨 Check 4: Building CryptoSage..."
BUILD_OUTPUT=$("$XCODEBUILD" \
    -scheme CryptoSage \
    -project "$XCODEPROJ" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    build 2>&1)

if echo "$BUILD_OUTPUT" | grep -q "BUILD SUCCEEDED"; then
    echo -e "  ${GREEN}✅ BUILD SUCCEEDED${NC}"
else
    echo -e "  ${RED}❌ BUILD FAILED${NC}"
    echo ""
    echo "  Errors:"
    echo "$BUILD_OUTPUT" | grep "error:" | head -10 | while read -r line; do
        echo -e "  ${RED}  $line${NC}"
    done
    ERRORS=$((ERRORS + 1))
fi
echo ""

# ─────────────────────────────────────────────
# CHECK 5: Firebase Functions Build
# ─────────────────────────────────────────────
FUNCTIONS_DIR="$PROJECT_DIR/firebase/functions"
if [ -d "$FUNCTIONS_DIR" ]; then
    echo "🔥 Check 5: Building Firebase Cloud Functions..."
    FIREBASE_OUTPUT=$(cd "$FUNCTIONS_DIR" && npm run build 2>&1)
    if echo "$FIREBASE_OUTPUT" | grep -qE "error TS|Error:|Cannot find"; then
        echo -e "  ${RED}❌ FIREBASE BUILD FAILED${NC}"
        echo "$FIREBASE_OUTPUT" | grep -E "error TS|Error:" | head -5 | while read -r line; do
            echo -e "  ${RED}  $line${NC}"
        done
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  ${GREEN}✅ Firebase functions compiled successfully${NC}"
    fi
    echo ""
fi

# ─────────────────────────────────────────────
# FULL MODE: Additional Checks
# ─────────────────────────────────────────────
if [ "$MODE" = "--full" ]; then
    echo "🔬 Full Mode: Running additional checks..."
    echo ""

    # Check for files with > 500 lines of changes (potential scope creep)
    echo "📏 Check 6: Large file changes..."
    git diff --stat HEAD~1 2>/dev/null | grep -E "\+.*-" | while read -r line; do
        ADDITIONS=$(echo "$line" | grep -oE "[0-9]+ insertion" | grep -oE "[0-9]+")
        if [ -n "$ADDITIONS" ] && [ "$ADDITIONS" -gt 500 ]; then
            FILE=$(echo "$line" | awk '{print $1}')
            echo -e "  ${YELLOW}⚠️  $FILE: $ADDITIONS+ lines added (review for scope creep)${NC}"
            WARNINGS=$((WARNINGS + 1))
        fi
    done
    echo ""

    # Check for hardcoded API keys or secrets
    echo "🔐 Check 7: Scanning for exposed secrets..."
    SECRETS=$(grep -rn "sk-\|AKIA\|AIza\|ghp_\|gho_\|password.*=.*[\"']" "$SOURCE_DIR" --include="*.swift" 2>/dev/null | \
        grep -v "\.example\|\.sample\|placeholder\|YOUR_\|REPLACE_\|TODO" | head -5)
    if [ -n "$SECRETS" ]; then
        echo -e "  ${RED}❌ Potential secrets found in code:${NC}"
        echo "$SECRETS" | while read -r line; do
            echo -e "  ${RED}  $line${NC}"
        done
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  ${GREEN}✅ No exposed secrets detected${NC}"
    fi
    echo ""
fi

# ─────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────
echo "================================="
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}❌ VERIFICATION FAILED: $ERRORS error(s), $WARNINGS warning(s)${NC}"
    echo -e "${RED}   DO NOT push to GitHub until errors are fixed.${NC}"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  VERIFICATION PASSED WITH WARNINGS: $WARNINGS warning(s)${NC}"
    echo -e "${YELLOW}   Review warnings before pushing.${NC}"
    exit 0
else
    echo -e "${GREEN}✅ ALL CHECKS PASSED — safe to push${NC}"
    exit 0
fi
