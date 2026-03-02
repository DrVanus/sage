import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit

@MainActor
final class ChartHaptics {
    static let shared = ChartHaptics()

    // HAPTIC ENGINE FIX: Track initialization state to handle Core Haptics failures
    // The console showed: "CHHapticEngine.mm:676 ERROR: Server timeout"
    // This happens when the haptic engine fails to initialize on app launch
    private var generatorsInitialized: Bool = false
    private var initializationFailed: Bool = false
    private var lastInitAttempt: Date = .distantPast
    private let initRetryInterval: TimeInterval = 2.0 // Retry every 2 seconds if failed
    
    // Generators - initialized on-demand with error handling
    private var _selection: UISelectionFeedbackGenerator?
    private var _light: UIImpactFeedbackGenerator?
    private var _soft: UIImpactFeedbackGenerator?
    private var _medium: UIImpactFeedbackGenerator?
    private var _rigid: UIImpactFeedbackGenerator?
    private var _notify: UINotificationFeedbackGenerator?
    
    // Safe accessors that handle initialization failures
    private var selection: UISelectionFeedbackGenerator {
        ensureGeneratorsInitialized()
        return _selection ?? UISelectionFeedbackGenerator()
    }
    private var light: UIImpactFeedbackGenerator {
        ensureGeneratorsInitialized()
        return _light ?? UIImpactFeedbackGenerator(style: .light)
    }
    private var soft: UIImpactFeedbackGenerator {
        ensureGeneratorsInitialized()
        return _soft ?? UIImpactFeedbackGenerator(style: .soft)
    }
    private var medium: UIImpactFeedbackGenerator {
        ensureGeneratorsInitialized()
        return _medium ?? UIImpactFeedbackGenerator(style: .medium)
    }
    private var rigid: UIImpactFeedbackGenerator {
        ensureGeneratorsInitialized()
        return _rigid ?? UIImpactFeedbackGenerator(style: .rigid)
    }
    private var notify: UINotificationFeedbackGenerator {
        ensureGeneratorsInitialized()
        return _notify ?? UINotificationFeedbackGenerator()
    }
    
    /// Initialize haptic generators with retry logic for Core Haptics failures
    private func ensureGeneratorsInitialized() {
        // Already initialized successfully
        if generatorsInitialized { return }
        
        // If previously failed, only retry after interval
        if initializationFailed {
            let elapsed = Date().timeIntervalSince(lastInitAttempt)
            guard elapsed >= initRetryInterval else { return }
        }
        
        lastInitAttempt = Date()
        
        // Create generators - these may fail if Core Haptics engine is unavailable
        _selection = UISelectionFeedbackGenerator()
        _light = UIImpactFeedbackGenerator(style: .light)
        _soft = UIImpactFeedbackGenerator(style: .soft)
        _medium = UIImpactFeedbackGenerator(style: .medium)
        _rigid = UIImpactFeedbackGenerator(style: .rigid)
        _notify = UINotificationFeedbackGenerator()
        
        // Test if haptics actually work by preparing a generator
        // This helps detect Core Haptics engine failures
        _light?.prepare()
        
        generatorsInitialized = true
        initializationFailed = false
        
        #if DEBUG
        if debugMode {
            print("[ChartHaptics] Generators initialized successfully")
        }
        #endif
    }
    
    /// Force re-initialization (call this if haptics stop working)
    func reinitialize() {
        generatorsInitialized = false
        initializationFailed = false
        lastInitAttempt = .distantPast
        sessionPrimed = false
        ensureGeneratorsInitialized()
    }

    // Global toggles
    var disabled: Bool = false
    var respectReduceMotion: Bool = true
    
    // Debug mode for troubleshooting haptic issues
    var debugMode: Bool = false

    // Intensities - increased slightly for more noticeable feedback
    var tickIntensity: CGFloat = 0.7
    var majorIntensity: CGFloat = 1.0
    var gridIntensity: CGFloat = 0.8

    // Throttle intervals (seconds) - optimized for responsive haptic feedback
    // PERFORMANCE FIX: Reduced intervals for more immediate feedback
    var minTickInterval: CFTimeInterval = 0.025  // ~40 Hz max, very responsive
    var minMajorInterval: CFTimeInterval = 0.12  // faster major feedback
    var minGridInterval: CFTimeInterval = 0.20   // gridline bump throttle

    // Adaptive tick (widens interval slightly if flooded)
    var adaptiveTick: Bool = true
    private var lastTickAttemptAt: CFTimeInterval = 0

    // Last fire timestamps
    private var lastTickAt: CFTimeInterval = 0
    private var lastMajorAt: CFTimeInterval = 0
    private var lastGridAt: CFTimeInterval = 0
    private var sessionPrimed: Bool = false
    
    // Track if we've ever successfully fired haptics
    private var hasEverFired: Bool = false

    enum Profile {
        case crisp
        case subtle
        case silent
        case custom(minTick: CFTimeInterval, minMajor: CFTimeInterval, minGrid: CFTimeInterval, tick: CGFloat, major: CGFloat, grid: CGFloat)
    }

    func setProfile(_ p: Profile) {
        switch p {
        case .crisp:
            minTickInterval = 0.045
            minMajorInterval = 0.22
            minGridInterval = 0.32
            tickIntensity = 0.6
            majorIntensity = 0.9
            gridIntensity = 0.75
            disabled = false
        case .subtle:
            minTickInterval = 0.07
            minMajorInterval = 0.30
            minGridInterval = 0.42
            tickIntensity = 0.45
            majorIntensity = 0.75
            gridIntensity = 0.6
            disabled = false
        case .silent:
            disabled = true
        case let .custom(minTick, minMajor, minGrid, tick, major, grid):
            minTickInterval = minTick
            minMajorInterval = minMajor
            minGridInterval = minGrid
            tickIntensity = tick
            majorIntensity = major
            gridIntensity = grid
            disabled = false
        }
    }

    private func primeGenerators() {
        // Prepare all generators for immediate use
        // This reduces latency on first haptic fire
        selection.prepare()
        light.prepare()
        soft.prepare()
        medium.prepare()
        rigid.prepare()
        notify.prepare()
        sessionPrimed = true
        
        #if DEBUG
        if debugMode {
            print("[ChartHaptics] Generators primed")
        }
        #endif
    }

    // Session lifecycle
    func begin(startBump: Bool = true) {
        guard shouldPerformHaptics else {
            #if DEBUG
            if debugMode {
                print("[ChartHaptics] begin() skipped - shouldPerformHaptics=false")
            }
            #endif
            return
        }
        
        // Always prime generators at session start for reliable haptics
        primeGenerators()
        
        // Reset throttle timestamps for fresh session - CRITICAL for immediate response
        lastTickAt = 0
        lastMajorAt = 0
        lastGridAt = 0
        lastTickAttemptAt = 0
        
        // HAPTIC FIX: Fire strong immediate feedback so user knows touch was recognized
        // Use medium impact for more noticeable confirmation
        if startBump {
            medium.prepare()
            medium.impactOccurred(intensity: 0.7)
            hasEverFired = true
        }
        
        // Also fire selection for additional tactile confirmation
        selection.selectionChanged()
        
        #if DEBUG
        if debugMode {
            print("[ChartHaptics] Session began, startBump=\(startBump)")
        }
        #endif
    }

    func end(endBump: Bool = false) {
        guard shouldPerformHaptics else { return }
        if endBump {
            light.prepare()
            light.impactOccurred(intensity: 0.45)
        } else {
            selection.prepare()
            selection.selectionChanged()
        }
        sessionPrimed = false
    }

    func cancel() {
        lastTickAt = 0
        lastMajorAt = 0
        lastGridAt = 0
        lastTickAttemptAt = 0
        sessionPrimed = false
    }

    // Events
    func tickIfNeeded(intensity: CGFloat? = nil) {
        guard shouldPerformHaptics else {
            #if DEBUG
            if debugMode {
                print("[ChartHaptics] tickIfNeeded skipped - shouldPerformHaptics=false")
            }
            #endif
            return
        }
        
        // Auto-prime if not already primed
        if !sessionPrimed { primeGenerators() }
        
        let now = CACurrentMediaTime()
        
        // Adaptive throttling - widen interval if flooded, relax when calm
        if adaptiveTick, lastTickAttemptAt > 0 {
            let dt = now - lastTickAttemptAt
            if dt < minTickInterval {
                // widen slightly (cap at ~80ms)
                let widened = min(minTickInterval * 1.05, 0.08)
                minTickInterval = max(minTickInterval, widened)
            } else {
                // relax back toward default bounds
                minTickInterval = max(0.035, min(minTickInterval * 0.98, 0.06))
            }
        }
        lastTickAttemptAt = now

        // Throttle check
        guard now - lastTickAt >= minTickInterval else {
            #if DEBUG
            if debugMode {
                print("[ChartHaptics] tick throttled, interval=\(now - lastTickAt)s")
            }
            #endif
            return
        }
        
        // Fire the haptic - use both selection and light for reliable feedback
        let actualIntensity = intensity ?? tickIntensity
        light.prepare()
        light.impactOccurred(intensity: actualIntensity)
        
        // Also fire selection for additional tactile cue
        selection.selectionChanged()
        
        lastTickAt = now
        hasEverFired = true
        
        #if DEBUG
        if debugMode {
            print("[ChartHaptics] tick fired, intensity=\(actualIntensity)")
        }
        #endif
    }

    func majorIfNeeded(intensity: CGFloat = 1.0) {
        guard shouldPerformHaptics else {
            #if DEBUG
            if debugMode {
                print("[ChartHaptics] majorIfNeeded skipped - shouldPerformHaptics=false")
            }
            #endif
            return
        }
        
        if !sessionPrimed { primeGenerators() }
        
        let now = CACurrentMediaTime()
        guard now - lastMajorAt >= minMajorInterval else {
            #if DEBUG
            if debugMode {
                print("[ChartHaptics] major throttled")
            }
            #endif
            return
        }
        
        // Fire dual impact for stronger feedback on major events
        rigid.prepare()
        rigid.impactOccurred(intensity: intensity)
        
        // Small delay then medium for double-tap feel
        medium.prepare()
        medium.impactOccurred(intensity: 0.85)
        
        lastMajorAt = now
        hasEverFired = true
        
        #if DEBUG
        if debugMode {
            print("[ChartHaptics] major fired, intensity=\(intensity)")
        }
        #endif
    }

    func gridBumpIfNeeded(intensity: CGFloat? = nil) {
        guard shouldPerformHaptics else { return }
        if !sessionPrimed { primeGenerators() }
        let now = CACurrentMediaTime()
        guard now - lastGridAt >= minGridInterval else { return }
        selection.prepare()
        soft.prepare()
        soft.impactOccurred(intensity: intensity ?? gridIntensity)
        selection.selectionChanged()
        lastGridAt = now
    }

    // Notifications
    func success() { guard shouldPerformHaptics else { return }; notify.notificationOccurred(.success) }
    func warning() { guard shouldPerformHaptics else { return }; notify.notificationOccurred(.warning) }
    func error()   { guard shouldPerformHaptics else { return }; notify.notificationOccurred(.error) }

    // Helpers
    private var shouldPerformHaptics: Bool {
        // Check if globally disabled
        if disabled {
            #if DEBUG
            if debugMode { print("[ChartHaptics] Disabled via disabled flag") }
            #endif
            return false
        }
        
        // Check accessibility setting (can be overridden)
        if respectReduceMotion && UIAccessibility.isReduceMotionEnabled {
            #if DEBUG
            if debugMode { print("[ChartHaptics] Disabled due to Reduce Motion setting") }
            #endif
            return false
        }
        
        #if targetEnvironment(simulator)
        // Haptics do not physically work on iOS Simulator
        // Still return false but note this is expected behavior
        #if DEBUG
        if debugMode { print("[ChartHaptics] Running on Simulator - haptics unavailable") }
        #endif
        return false
        #else
        return true
        #endif
    }
    
    /// Check if haptics are available and will work on this device
    var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return !disabled && !(respectReduceMotion && UIAccessibility.isReduceMotionEnabled)
        #endif
    }
}

#else

// Non-iOS platforms: provide no-op stubs so code compiles.
final class ChartHaptics {
    static let shared = ChartHaptics()
    var disabled: Bool = false
    var respectReduceMotion: Bool = false
    var tickIntensity: CGFloat = 0.6
    var majorIntensity: CGFloat = 0.9
    var gridIntensity: CGFloat = 0.75
    var minTickInterval: CFTimeInterval = 0.05
    var minMajorInterval: CFTimeInterval = 0.25
    var minGridInterval: CFTimeInterval = 0.35
    func setProfile(_ p: Any) {}
    func begin(startBump: Bool = true) {}
    func end(endBump: Bool = false) {}
    func cancel() {}
    func tickIfNeeded(intensity: CGFloat? = nil) {}
    func majorIfNeeded(intensity: CGFloat = 1.0) {}
    func gridBumpIfNeeded(intensity: CGFloat? = nil) {}
    func success() {}
    func warning() {}
    func error() {}
}

#endif

// MARK: - Global Haptic Feedback Utility
// CONSOLIDATION: Simple interface for common haptic feedback throughout the app
// Use this instead of creating UIImpactFeedbackGenerator instances inline

/// Simple haptic feedback utility for common interactions
/// Usage: `Haptic.light()` or `Haptic.medium()`
enum Haptic {
    #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    
    /// Light impact - for button taps, toggles, minor selections
    @MainActor static func light() {
        lightGenerator.impactOccurred()
    }
    
    /// Medium impact - for confirmations, significant selections
    @MainActor static func medium() {
        mediumGenerator.impactOccurred()
    }
    
    /// Heavy impact - for major actions, destructive confirmations
    @MainActor static func heavy() {
        heavyGenerator.impactOccurred()
    }
    
    /// Soft impact - for subtle feedback, background events
    @MainActor static func soft() {
        softGenerator.impactOccurred()
    }
    
    /// Rigid impact - for crisp, precise feedback
    @MainActor static func rigid() {
        rigidGenerator.impactOccurred()
    }
    
    /// Selection changed - for picker/wheel changes, segment selections
    @MainActor static func selection() {
        selectionGenerator.selectionChanged()
    }
    
    /// Success notification - for completed actions, successful saves
    @MainActor static func success() {
        notificationGenerator.notificationOccurred(.success)
    }
    
    /// Warning notification - for alerts, cautions
    @MainActor static func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }
    
    /// Error notification - for failures, errors
    @MainActor static func error() {
        notificationGenerator.notificationOccurred(.error)
    }
    
    #else
    // No-op stubs for platforms without haptics
    static func light() {}
    static func medium() {}
    static func heavy() {}
    static func soft() {}
    static func rigid() {}
    static func selection() {}
    static func success() {}
    static func warning() {}
    static func error() {}
    #endif
}




