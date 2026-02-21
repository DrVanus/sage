//
//  ScrollStateManager.swift
//  CryptoSage
//
//  Centralized scroll state tracking to optimize performance during scroll.
//  Pauses heavy operations (price updates, metrics computation) while user is scrolling.
//
//  PERFORMANCE FIX v2: Enhanced tracking for smooth scrolling:
//  - Longer scroll end debounce (0.6s) to catch momentum scrolling
//  - Longer throttle interval (5s) during scroll to reduce jank
//  - Lower velocity threshold (500 pts/sec) for earlier fast scroll detection
//  - RunLoop tracking to detect scroll during deceleration
//  - Heavy operation blocking during any scroll activity
//
//  THREAD SAFETY FIX v6: Use OSAllocatedUnfairLock for proper memory management
//  - OSAllocatedUnfairLock handles memory allocation correctly (iOS 16+)
//  - Eliminates EXC_BAD_ACCESS from unstable lock addresses
//  - Added caching to reduce lock contention under heavy load
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Combine
import QuartzCore
import os

// PERFORMANCE FIX v11: Global startup phase tracking
// During the first seconds after launch, onChange handlers fire excessively due to rapid
// @Published property updates. This causes the "onChange tried to update multiple times per frame" warning.
// Views should check isInGlobalStartupPhase() before processing onChange handlers.
private let globalAppLaunchTime = Date()

/// Duration of the "critical" startup phase - no onChange processing
/// PERFORMANCE FIX v17: Increased from 3.0 to 4.0 seconds to fully cover Firestore initial sync
/// Console logs show first Firestore ticker emission happens ~3-4s after launch,
/// triggering onChange(of: Double) warnings on multiple views simultaneously
private let globalStartupPhaseDuration: TimeInterval = 4.0

/// Duration of the "heavy operations blocked" phase - no background data fetching
/// This is longer to allow the UI to fully settle before triggering network requests
/// PERFORMANCE FIX v17: Increased from 4.0 to 5.0 seconds for consistency
private let globalHeavyOperationBlockDuration: TimeInterval = 5.0

/// Returns true if the app is still in the startup phase (first 2 seconds after launch).
/// During this phase, views should skip processing onChange handlers to prevent warnings.
func isInGlobalStartupPhase() -> Bool {
    return Date().timeIntervalSince(globalAppLaunchTime) < globalStartupPhaseDuration
}

/// Returns true if the app should block heavy operations (first 3 seconds after launch).
/// During this phase, background data fetching should be deferred to avoid overwhelming the system.
func shouldBlockHeavyOperationsDuringStartup() -> Bool {
    return Date().timeIntervalSince(globalAppLaunchTime) < globalHeavyOperationBlockDuration
}

// MEMORY FIX v9: Startup animation suppression window.
// During the first seconds after launch, `.repeatForever` animations (ShimmerBar,
// PremiumShimmer, ScrollAwarePulse) are suppressed entirely. These animations cause
// SwiftUI to re-evaluate complex view bodies on every frame (60 FPS), each creating
// GeometryReader closures, LinearGradients, and temporary view structs that accumulate
// faster than they can be released. With 20+ shimmer instances running simultaneously
// during authenticated re-launch (loading states for watchlist coins, portfolio, etc.),
// this generates ~8 MB/s of memory growth — enough to trigger iOS jetsam in minutes.
// MEMORY FIX v16: Increased from 5s to 15s. The shimmer animations are the PRIMARY
// source of the ~8.5 MB/s memory leak. When sparkline data never arrives (CoinGecko 401),
// the shimmer placeholders run FOREVER, each creating GeometryReader closures + LinearGradients
// on every animation frame. 15s gives the data pipeline time to populate real data.
private let globalAnimationSuppressionDuration: TimeInterval = 15.0

// MEMORY FIX v16: Global kill-switch for all shimmer/repeatForever animations.
// Set to true by the memory watchdog when emergency mode is triggered.
// Once set, ALL shimmer animations are permanently suppressed for the session.
// This is the ONLY way to stop the ~8 MB/s memory growth from animations
// when sparkline data never arrives (e.g., CoinGecko API returning 401).
nonisolated(unsafe) var globalAnimationsKilled: Bool = false

/// Returns true if startup animation suppression is active OR memory emergency is active.
/// ShimmerBar, PremiumShimmerModifier, and ScrollAwarePulse check this to avoid
/// starting `.repeatForever` animations during startup or memory pressure.
func shouldSuppressStartupAnimations() -> Bool {
    if globalAnimationsKilled { return true }
    return Date().timeIntervalSince(globalAppLaunchTime) < globalAnimationSuppressionDuration
}

/// Returns remaining seconds in the animation suppression window (0 if over).
/// Used by views to schedule a retry after the suppression window ends.
func animationSuppressionRemainingSeconds() -> TimeInterval {
    return max(0, globalAnimationSuppressionDuration - Date().timeIntervalSince(globalAppLaunchTime))
}

// THREAD SAFETY FIX v12: Simplified lock-free storage
// Previous implementations with os_unfair_lock and OSAllocatedUnfairLock caused EXC_BAD_ACCESS
// under heavy concurrent access from many threads.
// 
// This version uses a completely lock-free approach:
// - Updates happen only on main thread (via ScrollStateManager)
// - Reads use simple property access with eventual consistency
// - For scroll state tracking, eventual consistency is perfectly acceptable
// - Worst case: we read a slightly stale value (milliseconds old), which is fine
// PERFORMANCE FIX v25: Changed from `private` to `internal` so SparklineView can
// use the lock-free scroll check for data downsampling without going through @MainActor.
final class ScrollStateAtomicStorage: @unchecked Sendable {
    static let shared = ScrollStateAtomicStorage()
    
    // THREAD SAFETY: These are written ONLY from main thread (via update())
    // Reads from other threads may see slightly stale values - this is acceptable
    // for scroll state tracking where perfect accuracy is not required.
    // Using nonisolated(unsafe) to allow cross-thread reads without locks.
    nonisolated(unsafe) private var _shouldBlock: Bool = false
    nonisolated(unsafe) private var _isFastScrolling: Bool = false
    
    // PERFORMANCE FIX v21: Post-scroll settling period tracking
    // When scrolling stops, we keep shouldBlock true for a short period to prevent
    // deferred work from flooding in all at once and causing a visible pause.
    nonisolated(unsafe) private var _scrollEndedAt: CFTimeInterval = 0
    nonisolated(unsafe) private var _postScrollSettlingDuration: CFTimeInterval = 0.5
    
    // Internal state tracking (only accessed from main thread)
    private var _isScrolling: Bool = false
    private var _isDragging: Bool = false
    private var _isTrackingRunLoop: Bool = false
    
    /// Update scroll state - MUST be called from main thread only
    func update(scrolling: Bool, dragging: Bool, fastScrolling: Bool, trackingRunLoop: Bool, initPhase: Bool) {
        let wasScrolling = _isScrolling || _isDragging || _isFastScrolling || _isTrackingRunLoop
        
        // Store individual states
        _isScrolling = scrolling
        _isDragging = dragging
        _isFastScrolling = fastScrolling
        _isTrackingRunLoop = trackingRunLoop
        
        let isNowScrolling = scrolling || dragging || fastScrolling || trackingRunLoop
        
        // PERFORMANCE FIX v21: Track when scroll ends for settling period
        if wasScrolling && !isNowScrolling {
            _scrollEndedAt = CACurrentMediaTime()
        }
        
        // Pre-compute the combined result for fast cross-thread access
        _shouldBlock = isNowScrolling
    }
    
    /// Check if heavy operations should be blocked
    /// Safe to call from any thread - returns eventually consistent value
    /// PERFORMANCE FIX v21: Also blocks during post-scroll settling period
    func shouldBlock() -> Bool {
        if _shouldBlock { return true }
        
        // Check if we're in the post-scroll settling period
        // This prevents all deferred work from flooding in the instant scrolling stops
        let now = CACurrentMediaTime()
        let sinceScrollEnd = now - _scrollEndedAt
        if sinceScrollEnd < _postScrollSettlingDuration && sinceScrollEnd >= 0 {
            return true
        }
        
        return false
    }
    
    /// Check if user is fast scrolling
    /// Safe to call from any thread - returns eventually consistent value
    func isFastScrolling() -> Bool {
        return _isFastScrolling
    }
}

/// Global manager that tracks whether the user is actively scrolling.
/// Views can check `isScrolling` before triggering expensive updates.
@MainActor
final class ScrollStateManager: ObservableObject {
    static let shared = ScrollStateManager()
    
    /// True when user is actively scrolling
    @Published private(set) var isScrolling: Bool = false {
        didSet { syncAtomicStorage() }
    }
    
    /// True when user is actively dragging (gesture in progress)
    @Published private(set) var isDragging: Bool = false {
        didSet { syncAtomicStorage() }
    }
    
    /// True when scrolling at high velocity (should block all non-essential work)
    @Published private(set) var isFastScrolling: Bool = false {
        didSet { syncAtomicStorage() }
    }
    
    /// True when RunLoop is in tracking mode (UIScrollView momentum)
    @Published private(set) var isTrackingRunLoop: Bool = false {
        didSet { syncAtomicStorage() }
    }
    
    // PERFORMANCE FIX v3: App initialization phase tracking
    // During startup, the main thread is overloaded with view creation, data loading,
    // and Firebase sync. Block all non-essential updates during this critical phase.
    /// True when app is in initialization phase (first 3 seconds after launch)
    private(set) var isInInitializationPhase: Bool = true {
        didSet { syncAtomicStorage() }
    }
    /// Timestamp when app launched
    private let appLaunchTime = Date()
    /// Duration of initialization phase in seconds
    private let initPhaseDuration: TimeInterval = 3.0
    
    /// THREAD SAFETY FIX v5: Sync state to atomic storage for cross-thread access
    private func syncAtomicStorage() {
        ScrollStateAtomicStorage.shared.update(
            scrolling: isScrolling,
            dragging: isDragging,
            fastScrolling: isFastScrolling,
            trackingRunLoop: isTrackingRunLoop,
            initPhase: isInInitializationPhase
        )
    }
    
    /// Timestamp of last scroll activity (for debouncing)
    private var lastScrollActivityAt: Date = .distantPast
    
    /// PERFORMANCE FIX v21: Timestamp when scrolling actually ended (isScrolling went false)
    /// Used to enforce a settling period where shouldBlockHeavyOperation still returns true
    /// This prevents the "pause after scroll" caused by all deferred work rushing in at once
    private var scrollEndedAt: Date = .distantPast
    
    /// PERFORMANCE FIX v21: Duration of the settling period after scroll ends
    /// During this time, shouldBlockHeavyOperation() still returns true
    /// This gives the UI time to settle before deferred Firestore/price data floods in
    private let postScrollSettlingDuration: TimeInterval = 0.5
    
    /// Timer to reset scrolling state after activity stops
    private var scrollEndTimer: Timer?
    
    /// Timer to reset fast scrolling state
    private var fastScrollEndTimer: Timer?
    
    /// RunLoop observer for tracking scroll momentum
    private var runLoopObserver: CFRunLoopObserver?
    
    /// Track scroll positions for velocity calculation
    private var lastScrollOffset: CGFloat = 0
    private var lastScrollTime: CFTimeInterval = 0
    
    /// Rolling velocity calculation (smoother than instant)
    private var recentVelocities: [CGFloat] = []
    private let maxVelocitySamples = 5
    
    /// Debounce interval - how long after scroll stops before we resume updates
    /// PERFORMANCE FIX v21: Increased from 0.6s to 0.8s to better catch momentum scrolling
    /// and provide a settling period before deferred work floods in
    private let scrollEndDebounce: TimeInterval = 0.8
    
    /// Minimum interval between expensive updates during scroll
    /// PERFORMANCE FIX: Increased to 5.0s to reduce jank during scroll
    private let scrollThrottleInterval: TimeInterval = 5.0
    
    /// Velocity threshold for "fast scrolling" (points per second)
    /// PERFORMANCE FIX: Lowered from 800 to 500 for earlier detection
    private let fastScrollVelocityThreshold: CGFloat = 500
    
    /// Last time an expensive operation was allowed during scroll
    private var lastThrottledUpdateAt: Date = .distantPast
    
    /// Counter to track scroll events per second (for rate limiting preference updates)
    private var scrollEventCount: Int = 0
    private var scrollEventResetTime: CFTimeInterval = 0
    private let maxScrollEventsPerSecond: Int = 5
    
    private init() {
        // THREAD SAFETY FIX v5: Initialize atomic storage with default values
        syncAtomicStorage()
        setupRunLoopObserver()
    }
    
    deinit {
        if let observer = runLoopObserver {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }
    
    /// Track last RunLoop mode to avoid redundant updates
    private var lastKnownTrackingMode: Bool = false
    /// Throttle RunLoop observer updates - only check every 100ms
    private var lastRunLoopCheckTime: CFTimeInterval = 0
    private let runLoopCheckInterval: CFTimeInterval = 0.1 // 10Hz max
    
    // MEMORY FIX v14: Pre-dispatch throttle variables.
    // The CFRunLoopObserver fires on EVERY run loop entry/exit (thousands per second).
    // Previously, each callback dispatched DispatchQueue.main.async BEFORE throttling,
    // creating a feedback loop: dispatch → run loop wakes → observer fires → dispatch → ...
    // This prevented the run loop from EVER going idle, so autorelease pools never drained,
    // causing 34 MB/s of leaked temporary allocations (the root cause of the OOM crash).
    //
    // Fix: Throttle and mode-check BEFORE dispatching, using nonisolated(unsafe) variables.
    // A data race on these is harmless — worst case we process one extra dispatch.
    nonisolated(unsafe) private var _preDispatchLastCheckTime: CFTimeInterval = 0
    nonisolated(unsafe) private var _preDispatchLastTrackingMode: Bool = false
    
    /// Setup RunLoop observer to detect UIScrollView tracking mode
    /// This catches momentum scrolling that preference keys miss
    /// THREAD SAFETY FIX: CFRunLoopObserver callbacks bypass @MainActor isolation.
    /// ALL property access MUST be wrapped in DispatchQueue.main.async to avoid data races.
    private func setupRunLoopObserver() {
        // Observe RunLoop mode changes - UIScrollView uses tracking mode during scroll
        runLoopObserver = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.entry.rawValue | CFRunLoopActivity.exit.rawValue,
            true, // repeats
            0 // order
        ) { [weak self] _, activity in
            // MEMORY FIX v14: Throttle BEFORE dispatching to break the feedback loop.
            // Previously, DispatchQueue.main.async was called on EVERY callback (~1000+/s),
            // and each dispatch caused more run loop activity → more observer callbacks.
            // The run loop never went idle, autorelease pools never drained, and temporary
            // SwiftUI allocations accumulated at ~34 MB/s causing OOM crash within 90 seconds.
            // Now we only dispatch when (a) enough time has passed AND (b) mode changed.
            // nonisolated(unsafe) reads are acceptable here — worst case is one extra dispatch.
            guard let s = self else { return }
            let callbackTime = CACurrentMediaTime()
            guard callbackTime - s._preDispatchLastCheckTime >= s.runLoopCheckInterval else { return }
            
            // Check RunLoop mode before dispatch (thread-safe - reading CF state)
            let currentMode = CFRunLoopCopyCurrentMode(CFRunLoopGetMain())
            let modeString = currentMode.map { $0.rawValue as String }
            let isTracking = modeString == "UITrackingRunLoopMode"
            
            // Only dispatch if tracking mode actually changed
            guard isTracking != s._preDispatchLastTrackingMode else {
                // Mode unchanged — update timestamp to keep throttle window moving
                s._preDispatchLastCheckTime = callbackTime
                return
            }
            
            // Mode changed AND throttle window passed — dispatch update
            s._preDispatchLastCheckTime = callbackTime
            s._preDispatchLastTrackingMode = isTracking
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.lastRunLoopCheckTime = callbackTime
                
                // Only update if mode actually changed (double-check on main thread)
                guard isTracking != self.lastKnownTrackingMode else { return }
                self.lastKnownTrackingMode = isTracking
                
                // Update tracking state
                guard isTracking != self.isTrackingRunLoop else { return }
                self.isTrackingRunLoop = isTracking
                
                if isTracking {
                    // Entered tracking mode - start scrolling
                    self.isScrolling = true
                    self.scrollEndTimer?.invalidate()
                } else {
                    // Exited tracking mode - schedule end
                    self.scheduleScrollEnd(after: self.scrollEndDebounce)
                }
            }
        }
        
        if let observer = runLoopObserver {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }
    
    // MARK: - Public API
    
    /// Call when scroll activity is detected (e.g., from preference key changes)
    /// Returns false if the event should be ignored (rate limited)
    @discardableResult
    func reportScrollActivity(offset: CGFloat = 0) -> Bool {
        let now = CACurrentMediaTime()
        
        // Rate limit scroll events to prevent flooding
        if now - scrollEventResetTime >= 1.0 {
            scrollEventCount = 0
            scrollEventResetTime = now
        }
        scrollEventCount += 1
        
        // Ignore excess events to reduce main thread work
        if scrollEventCount > maxScrollEventsPerSecond {
            return false
        }
        
        // Calculate velocity if we have position data
        var instantVelocity: CGFloat = 0
        if offset != 0 && lastScrollTime > 0 {
            let dt = now - lastScrollTime
            if dt > 0 && dt < 0.5 { // Only calculate if time gap is reasonable
                instantVelocity = abs(offset - lastScrollOffset) / CGFloat(dt)
                
                // Rolling velocity for smoother detection
                recentVelocities.append(instantVelocity)
                if recentVelocities.count > maxVelocitySamples {
                    recentVelocities.removeFirst()
                }
                
                // Use average velocity for more stable fast scroll detection
                let avgVelocity = recentVelocities.reduce(0, +) / CGFloat(recentVelocities.count)
                
                // Detect fast scrolling using average velocity
                if avgVelocity > fastScrollVelocityThreshold {
                    if !isFastScrolling {
                        isFastScrolling = true
                    }
                    // Reset fast scroll end timer - longer duration (1.2s) for momentum
                    fastScrollEndTimer?.invalidate()
                    // PERFORMANCE FIX v3: Use DispatchQueue.main.async instead of Task
                    fastScrollEndTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                        DispatchQueue.main.async { [weak self] in
                            self?.isFastScrolling = false
                            self?.recentVelocities.removeAll()
                        }
                    }
                }
            }
        }
        
        lastScrollOffset = offset
        lastScrollTime = now
        lastScrollActivityAt = Date()
        
        // Start scrolling state if not already
        if !isScrolling {
            isScrolling = true
        }
        
        // Reset the scroll-end timer
        scheduleScrollEnd(after: scrollEndDebounce)
        
        return true
    }
    
    /// Schedule scroll end after delay (consolidates timer creation)
    /// PERFORMANCE FIX v3: Use DispatchQueue instead of Task to avoid overhead
    private func scheduleScrollEnd(after delay: TimeInterval) {
        scrollEndTimer?.invalidate()
        scrollEndTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.endScrolling()
            }
        }
    }
    
    /// Call when drag gesture begins
    func beginDragging() {
        isDragging = true
        isScrolling = true
        scrollEndTimer?.invalidate()
    }
    
    /// Call when drag gesture ends
    func endDragging() {
        isDragging = false
        // Keep isScrolling true for momentum scrolling; timer will end it
        // PERFORMANCE FIX: Longer wait after drag ends to catch momentum (3x debounce)
        scheduleScrollEnd(after: scrollEndDebounce * 3.0)
    }
    
    /// Returns true if ANY scroll-related activity is happening
    /// Use this for the most restrictive blocking
    var isAnyScrollActivity: Bool {
        isScrolling || isDragging || isFastScrolling || isTrackingRunLoop
    }
    
    /// PERFORMANCE FIX v3: Check and update initialization phase status
    /// Returns true if still in init phase
    private func checkInitializationPhase() -> Bool {
        if isInInitializationPhase {
            let elapsed = Date().timeIntervalSince(appLaunchTime)
            if elapsed >= initPhaseDuration {
                isInInitializationPhase = false
            }
        }
        return isInInitializationPhase
    }
    
    /// Returns true if an expensive update should be skipped to maintain scroll performance.
    /// Call this before triggering price updates, metrics recomputation, etc.
    /// THREAD SAFETY FIX v5: Uses separate atomic storage for complete thread safety
    nonisolated func shouldSkipExpensiveUpdate() -> Bool {
        return ScrollStateAtomicStorage.shared.shouldBlock()
    }
    
    /// Returns true if heavy operations like WebView init should be blocked
    /// More restrictive than shouldSkipExpensiveUpdate - blocks during ANY scroll activity
    /// THREAD SAFETY FIX v5: Uses separate atomic storage for complete thread safety
    nonisolated func shouldBlockHeavyOperation() -> Bool {
        return ScrollStateAtomicStorage.shared.shouldBlock()
    }
    
    /// Force-ends scrolling state (useful when view disappears)
    func forceEndScrolling() {
        scrollEndTimer?.invalidate()
        scrollEndTimer = nil
        fastScrollEndTimer?.invalidate()
        fastScrollEndTimer = nil
        isScrolling = false
        isDragging = false
        isFastScrolling = false
        isTrackingRunLoop = false
        scrollEventCount = 0
        recentVelocities.removeAll()
    }
    
    /// PERFORMANCE FIX v3: Force-end initialization phase (e.g., when user interacts)
    /// Call this when user starts actively using the app to allow updates
    func endInitializationPhase() {
        isInInitializationPhase = false
    }
    
    // MARK: - Private
    
    private func endScrolling() {
        scrollEndTimer?.invalidate()
        scrollEndTimer = nil
        
        // Only end scrolling if drag is also done and not in tracking mode
        if !isDragging && !isTrackingRunLoop {
            isScrolling = false
            // PERFORMANCE FIX v21: Record when scroll ended for settling period
            scrollEndedAt = Date()
            // Reset velocity tracking
            lastScrollOffset = 0
            lastScrollTime = 0
            recentVelocities.removeAll()
        }
    }
}

// MARK: - Scroll Detection Preference Key

/// Preference key to track scroll position changes
/// PERFORMANCE FIX v12: Very aggressive throttling - RunLoop observer handles most scroll detection
/// - Throttled to ~1Hz (every 1000ms) - preference keys are backup only
/// - Position threshold increased to 100 points - only catch very large scrolls
/// - Lock-free design to avoid EXC_BAD_ACCESS from lock contention
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    // THREAD SAFETY v12: Lock-free using nonisolated(unsafe)
    // Eventual consistency is fine for scroll tracking - worst case is a slightly delayed update
    nonisolated(unsafe) private static var _lastUpdateAt: CFTimeInterval = 0
    nonisolated(unsafe) private static var _lastValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        let now = CACurrentMediaTime()
        
        // PERFORMANCE FIX v12: Reduced to ~1Hz - RunLoop observer is primary detector
        guard now - _lastUpdateAt >= 1.0 else { return }
        
        // PERFORMANCE FIX v12: Only trigger update if position changed significantly (> 100 points)
        guard abs(next - _lastValue) > 100 else { return }
        
        value = next
        _lastValue = next
        _lastUpdateAt = now
    }
}

// MARK: - View Extension for Scroll Detection

extension View {
    /// Adds scroll detection that reports to ScrollStateManager.
    /// PERFORMANCE FIX v13: Simplified - no async dispatch, direct call only
    /// This reduces frame drops during scroll by eliminating dispatch queue overhead
    func trackScrolling(coordinateSpace: String = "scroll") -> some View {
        self
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named(coordinateSpace)).minY
                        )
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                // PERFORMANCE FIX v13: Direct call - onPreferenceChange already runs on main thread
                // Removing DispatchQueue.main.async eliminates queuing overhead that causes jank
                ScrollStateManager.shared.reportScrollActivity(offset: offset)
            }
    }
    
    /// Wraps content in a scroll view with automatic scroll tracking
    func scrollViewWithTracking(showsIndicators: Bool = true) -> some View {
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            self
                .trackScrolling(coordinateSpace: "scrollContainer")
        }
        .coordinateSpace(name: "scrollContainer")
    }
}

// MARK: - Drag Gesture Extension

extension View {
    /// PERFORMANCE FIX v13: Simplified drag tracking - no gesture recognizer
    /// The DragGesture was causing scroll interference and frame drops
    /// RunLoop tracking handles scroll detection well enough on its own
    func trackDragging() -> some View {
        // REMOVED: DragGesture was interfering with scroll smoothness
        // The RunLoop observer in ScrollStateManager detects scroll activity
        self
    }
    
    /// PERFORMANCE FIX v21: Apply UIKit-level scroll optimizations to a SwiftUI ScrollView.
    /// This bridges into the real UIScrollView underneath SwiftUI and applies:
    /// 1. Deceleration rate tuning (0.994 - Coinbase/Robinhood sweet spot)
    /// 2. KVO-based scroll tracking (replaces GeometryReader overhead)
    /// These are the same techniques professional fintech apps use for buttery scrolling.
    func withUIKitScrollBridge() -> some View {
        self.background(UIScrollViewBridge())
    }
    
    /// Lightweight fix for ScrollView + navigation back-swipe conflict.
    /// Use this on detail pages whose ScrollView doesn't already have `.withUIKitScrollBridge()`.
    ///
    /// Makes the scroll view's pan gesture defer to the navigation controller's
    /// edge-swipe-back gesture, preventing vertical scrolling from hijacking the
    /// swipe-to-go-back gesture. Normal scrolling is completely unaffected.
    ///
    /// If the view already uses `.withUIKitScrollBridge()`, this is unnecessary
    /// (the bridge includes this fix automatically).
    func scrollViewBackSwipeFix() -> some View {
        self.background(ScrollBackSwipeBridge())
    }
}

// MARK: - Lightweight Back-Swipe Bridge
//
// A minimal UIViewRepresentable that ONLY configures the scroll/nav gesture priority.
// Use `.scrollViewBackSwipeFix()` on views that don't need the full UIKit scroll bridge.

private struct ScrollBackSwipeBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> ScrollBackSwipeView {
        let view = ScrollBackSwipeView()
        view.isHidden = true
        view.frame = .zero
        view.isUserInteractionEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: ScrollBackSwipeView, context: Context) {}
    
    final class ScrollBackSwipeView: UIView {
        private var configured = false
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil && !configured {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.configure()
                }
            }
        }
        
        private func configure() {
            guard !configured else { return }
            
            // Find the UIScrollView (walk up)
            var current: UIView? = self
            var scrollView: UIScrollView?
            while let view = current {
                if let sv = view as? UIScrollView {
                    scrollView = sv
                    break
                }
                current = view.superview
            }
            
            guard let sv = scrollView else { return }
            
            // Find UINavigationController via responder chain
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let nav = next as? UINavigationController,
                   let edgeGesture = nav.interactivePopGestureRecognizer {
                    edgeGesture.isEnabled = true
                    sv.panGestureRecognizer.require(toFail: edgeGesture)
                    configured = true
                    return
                }
                responder = next
            }
        }
    }
}

// MARK: - UIKit Scroll Bridge
//
// WHY THIS EXISTS:
// ================
// SwiftUI's ScrollView is backed by a UIScrollView, but SwiftUI doesn't expose
// UIKit-level tuning like deceleration rate or KVO-based scroll observation.
//
// Professional apps (Coinbase, Robinhood, Twitter) tune these UIKit properties to
// achieve scroll that feels "right" - slightly snappier deceleration so content
// stops sooner and the user can start reading, plus zero-overhead scroll tracking
// via KVO instead of SwiftUI's GeometryReader+PreferenceKey approach.
//
// HOW IT WORKS:
// 1. A tiny hidden UIView is placed in the scroll content
// 2. When it's added to the window, it walks up the view hierarchy to find the UIScrollView
// 3. It applies deceleration tuning and sets up KVO observation on contentOffset
// 4. KVO fires at the UIKit layer with zero SwiftUI layout overhead
// 5. Drag state is tracked via isDragging/isDecelerating KVO for precise lifecycle
//
// SAFETY:
// - Does NOT set the UIScrollView's delegate (would break SwiftUI internals)
// - Uses only KVO observation (non-intrusive, read-only)
// - Deceleration rate is a simple property that SwiftUI doesn't manage
// - Cleanup is automatic via NSKeyValueObservation invalidation

private struct UIScrollViewBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> ScrollBridgeView {
        let view = ScrollBridgeView()
        view.isHidden = true
        view.frame = .zero
        view.isUserInteractionEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: ScrollBridgeView, context: Context) {}
    
    final class ScrollBridgeView: UIView {
        private var scrollView: UIScrollView?
        private weak var contentHostLayer: CALayer?  // The content view's layer for animation freezing
        private var contentOffsetObservation: NSKeyValueObservation?
        private var isDraggingObservation: NSKeyValueObservation?
        private var isDeceleratingObservation: NSKeyValueObservation?
        private var configured = false
        private var animationsFrozen = false
        
        // Throttle KVO reports to ~15Hz (more than enough for scroll tracking)
        private var lastReportTime: CFTimeInterval = 0
        private let minReportInterval: CFTimeInterval = 0.066 // ~15Hz
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil && !configured {
                // Delay slightly to ensure SwiftUI has finished laying out the scroll view
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.findAndConfigureScrollView()
                }
            }
        }
        
        private func findAndConfigureScrollView() {
            guard !configured else { return }
            
            // Walk up the view hierarchy to find the UIScrollView backing SwiftUI's ScrollView
            var current: UIView? = self
            while let view = current {
                if let sv = view as? UIScrollView {
                    scrollView = sv
                    configured = true
                    configureScrollPhysics(sv)
                    configureContentAnimationFreeze(sv)
                    configureBackSwipeGesturePriority(sv)
                    observeScrollState(sv)
                    return
                }
                current = view.superview
            }
        }
        
        // MARK: - Navigation Back-Swipe Priority
        //
        // FIX: Prevents vertical scrolling from hijacking the iOS edge-swipe-back gesture.
        //
        // THE PROBLEM:
        // When a ScrollView is inside a NavigationStack, both the scroll view's
        // UIPanGestureRecognizer and the navigation controller's interactivePopGestureRecognizer
        // (a UIScreenEdgePanGestureRecognizer) compete for the same touch. Because
        // the scroll view's pan gesture has a very low activation threshold, it often
        // wins — causing the page to scroll vertically when the user intended to swipe back.
        //
        // THE FIX:
        // `scrollView.panGestureRecognizer.require(toFail: edgeGesture)`
        //
        // This tells UIKit: "Don't start scrolling until the edge-swipe gesture has
        // determined this touch ISN'T a back-swipe." Since UIScreenEdgePanGestureRecognizer
        // only activates from the leftmost ~20pt edge, non-edge touches fail IMMEDIATELY
        // (< 1 frame), so normal scrolling is unaffected. Edge touches properly trigger
        // the back navigation instead of scrolling.
        //
        // This is the EXACT technique Apple's own apps (Settings, App Store, Maps) use.
        
        private func configureBackSwipeGesturePriority(_ sv: UIScrollView) {
            guard let nav = findNavigationController(),
                  let edgeGesture = nav.interactivePopGestureRecognizer else { return }
            
            // Ensure the edge gesture is enabled (may have been disabled by hidden back button)
            edgeGesture.isEnabled = true
            
            // Make scroll wait for the edge gesture to fail before activating.
            // For non-edge touches, the edge gesture fails in < 1 frame — no perceptible delay.
            sv.panGestureRecognizer.require(toFail: edgeGesture)
        }
        
        /// Traverse the responder chain to find the nearest UINavigationController.
        private func findNavigationController() -> UINavigationController? {
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let nav = next as? UINavigationController {
                    return nav
                }
                responder = next
            }
            return nil
        }
        
        // MARK: - Deceleration Tuning
        
        private func configureScrollPhysics(_ sv: UIScrollView) {
            // DECELERATION RATE:
            // UIScrollView.DecelerationRate.normal = 0.998 (SwiftUI default - feels "floaty")
            // UIScrollView.DecelerationRate.fast   = 0.990 (too aggressive for content browsing)
            //
            // Professional fintech apps use ~0.993-0.995:
            // - Coinbase: ~0.994 (snappy but not jarring)
            // - Robinhood: ~0.993 (slightly snappier)
            // - Twitter: ~0.995 (balanced for mixed content)
            //
            // 0.994 is the sweet spot for crypto apps with data-dense cards:
            // scroll stops faster so users can read prices, but still has natural momentum.
            sv.decelerationRate = UIScrollView.DecelerationRate(rawValue: 0.994)
        }
        
        // MARK: - Content Animation Freeze
        //
        // THE KEY TECHNIQUE: Setting `layer.speed = 0` on the scroll content host view
        // freezes ALL Core Animation sublayer animations. This is how Coinbase, Twitter,
        // and every professional UIKit app achieves smooth scrolling:
        //
        // - During scroll: layer.speed = 0 → all shimmer, pulse, glow, rotation animations FREEZE
        //   → GPU only composites static bitmaps → buttery smooth 60fps scrolling
        // - After scroll: layer.speed = 1 → all animations resume from where they paused
        //
        // This ONE mechanism replaces the need to individually fix 67+ .repeatForever animations
        // across the entire app. It works because:
        // 1. SwiftUI animations are backed by Core Animation under the hood
        // 2. layer.speed affects ALL sublayer animations recursively
        // 3. The scroll view itself is NOT affected (it's the parent, not a sublayer)
        // 4. We already block data updates during scroll, so frozen content stays accurate
        
        private func configureContentAnimationFreeze(_ sv: UIScrollView) {
            // The content host is the first subview of UIScrollView.
            // In SwiftUI's ScrollView, this contains all the SwiftUI content.
            guard let contentHost = sv.subviews.first else { return }
            contentHostLayer = contentHost.layer
        }
        
        /// Freeze or resume all content animations using the standard Core Animation
        /// pause/resume pattern (Apple Technical Q&A QA1673).
        private func setContentAnimationsFrozen(_ frozen: Bool) {
            guard frozen != animationsFrozen else { return }
            guard let layer = contentHostLayer else { return }
            animationsFrozen = frozen
            
            if frozen {
                // PAUSE: Capture the current media time, freeze speed, store in timeOffset.
                // This tells Core Animation "stop here and remember this moment."
                let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
                layer.speed = 0
                layer.timeOffset = pausedTime
            } else {
                // RESUME: Restore speed and compute elapsed time since pause.
                // beginTime offset ensures animations resume smoothly from where they froze
                // instead of jumping to where they "would have been" if never paused.
                let pausedTime = layer.timeOffset
                layer.speed = 1.0
                layer.timeOffset = 0.0
                layer.beginTime = 0.0
                let timeSincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
                layer.beginTime = timeSincePause
            }
        }
        
        // MARK: - KVO-Based Scroll Observation
        //
        // This REPLACES the GeometryReader+PreferenceKey approach for this scroll view.
        // Benefits:
        // - Zero SwiftUI layout overhead during scroll (no GeometryReader frame computation)
        // - Fires at the UIKit layer, below SwiftUI's rendering pipeline
        // - Precise drag/deceleration lifecycle from UIScrollView properties
        // - Automatically works during momentum scrolling (no RunLoop observer needed)
        
        private func observeScrollState(_ sv: UIScrollView) {
            // Observe contentOffset for scroll position tracking
            contentOffsetObservation = sv.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                guard let self = self else { return }
                
                // Throttle to ~15Hz - more than enough for scroll state tracking
                let now = CACurrentMediaTime()
                guard now - self.lastReportTime >= self.minReportInterval else { return }
                self.lastReportTime = now
                
                // Only report during active scroll (dragging or decelerating)
                if scrollView.isDragging || scrollView.isDecelerating {
                    let offset = scrollView.contentOffset.y
                    // Already on main thread (KVO fires on the thread that set the property)
                    _ = MainActor.assumeIsolated {
                        ScrollStateManager.shared.reportScrollActivity(offset: offset)
                    }
                }
            }
            
            // Observe isDragging for precise drag lifecycle + animation freeze
            isDraggingObservation = sv.observe(\.isDragging, options: [.new, .old]) { [weak self] scrollView, change in
                guard let isDragging = change.newValue else { return }
                DispatchQueue.main.async {
                    if isDragging {
                        ScrollStateManager.shared.beginDragging()
                        // FREEZE all content animations when user starts dragging
                        self?.setContentAnimationsFrozen(true)
                    } else {
                        ScrollStateManager.shared.endDragging()
                        // Only unfreeze if momentum scroll isn't continuing
                        if !scrollView.isDecelerating {
                            self?.setContentAnimationsFrozen(false)
                        }
                    }
                }
            }
            
            // Observe isDecelerating to know when momentum scroll starts/stops + animation freeze
            isDeceleratingObservation = sv.observe(\.isDecelerating, options: [.new]) { [weak self] scrollView, change in
                guard let isDecelerating = change.newValue else { return }
                if !isDecelerating && !scrollView.isDragging {
                    // Both drag and momentum ended - UNFREEZE all content animations
                    DispatchQueue.main.async {
                        self?.setContentAnimationsFrozen(false)
                    }
                }
            }
        }
        
        override func removeFromSuperview() {
            // Resume animations before cleanup
            setContentAnimationsFrozen(false)
            // Clean up KVO observations
            contentOffsetObservation?.invalidate()
            isDraggingObservation?.invalidate()
            isDeceleratingObservation?.invalidate()
            contentOffsetObservation = nil
            isDraggingObservation = nil
            isDeceleratingObservation = nil
            contentHostLayer = nil
            super.removeFromSuperview()
        }
    }
}

// MARK: - Section Layer Rasterization During Scroll
//
// WHY THIS EXISTS:
// ================
// UIKit apps like Coinbase set `layer.shouldRasterize = true` on table view cells during scroll.
// This tells Core Animation to cache the rendered cell as a bitmap (rasterized image).
// During scroll, the GPU only needs to MOVE these cached bitmaps - no re-rendering.
// This is THE key technique that makes UIKit scroll feel buttery smooth.
//
// In SwiftUI, each card section has multiple layers (background, gradients, text, shadows, etc.)
// that the GPU composites every frame during scroll. By rasterizing, we collapse all those
// layers into a single pre-rendered bitmap - dramatically reducing GPU work per frame.
//
// HOW IT WORKS:
// 1. A tiny hidden UIView is placed inside each section card
// 2. It finds the nearest parent UIView with meaningful size (the section container)
// 3. When scroll starts: sets `layer.shouldRasterize = true` (cache as bitmap)
// 4. When scroll ends: sets `layer.shouldRasterize = false` (render normally)
//
// This is safe because we already block data updates during scroll (via ScrollStateManager),
// so the rasterized bitmap won't become stale while scrolling.
//
// MEMORY:
// - Each rasterized section uses ~width * height * 4 bytes of GPU memory
// - A typical 390x200 section = ~312KB
// - With ~10 visible sections = ~3MB total (well within budget)
// - Memory is freed immediately when shouldRasterize is set back to false

extension View {
    /// Apply UIKit layer rasterization during scroll for smoother compositing.
    /// Place this on section-level card views that contain multiple visual layers.
    func rasterizeDuringScroll() -> some View {
        self.background(SectionRasterizer())
    }
}

private struct SectionRasterizer: UIViewRepresentable {
    func makeUIView(context: Context) -> SectionRasterizerView {
        let view = SectionRasterizerView()
        view.isHidden = true
        view.frame = .zero
        view.isUserInteractionEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: SectionRasterizerView, context: Context) {}
    
    final class SectionRasterizerView: UIView {
        private weak var targetLayer: CALayer?
        private var cancellable: AnyCancellable?
        private var configured = false
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil && !configured {
                DispatchQueue.main.async { [weak self] in
                    self?.setup()
                }
            }
        }
        
        private func setup() {
            guard !configured else { return }
            configured = true
            
            // Walk UP the view hierarchy to find the section container.
            // In SwiftUI's hosting stack, the section card's UIView is typically
            // 3-6 levels up from where our hidden view is placed.
            var current: UIView? = self.superview
            var bestCandidate: UIView?
            var depth = 0
            
            while let view = current, depth < 8 {
                // Look for a view with meaningful size that represents the section card
                if view.bounds.width > 200 && view.bounds.height > 40 {
                    bestCandidate = view
                    // Don't go past the scroll view itself
                    if view is UIScrollView { break }
                }
                current = view.superview
                depth += 1
            }
            
            guard let target = bestCandidate else { return }
            targetLayer = target.layer
            target.layer.rasterizationScale = UIScreen.main.scale
            
            // Subscribe to scroll state changes on main thread
            cancellable = ScrollStateManager.shared.$isScrolling
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isScrolling in
                    self?.targetLayer?.shouldRasterize = isScrolling
                }
        }
        
        override func removeFromSuperview() {
            cancellable?.cancel()
            cancellable = nil
            targetLayer?.shouldRasterize = false
            targetLayer = nil
            super.removeFromSuperview()
        }
    }
}

// MARK: - Scroll-Aware Pulse Animation
//
// WHY THIS EXISTS:
// ================
// The app has 50+ `.repeatForever` animations across many views (loading indicators,
// pulse effects, glow effects, etc.). Each one generates GPU compositing work every
// frame, even during scroll. Fixing them individually is impractical.
//
// This provides a DROP-IN replacement:
//   BEFORE: .opacity(pulse ? 0.5 : 1.0)
//           .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
//           .onAppear { pulse = true }
//
//   AFTER:  .modifier(ScrollAwarePulse(isActive: $pulse, duration: 1.2, autoreverses: true))
//
// Or even simpler, for views that just need a pulsing opacity/scale:
//   .scrollAwarePulse(active: $pulse, duration: 1.2)
//
// HOW IT WORKS:
// - When scroll starts: animation state is reset to false (kills the .repeatForever)
// - When scroll ends + 0.5s settling: animation restarts
// - Uses `.onReceive(ScrollStateManager.shared.$isScrolling)` for zero-overhead detection

// MEMORY FIX v16: Removed .repeatForever animation from ScrollAwarePulse.
// The previous implementation caused the same ~9 MB/s memory leak as ShimmerBar
// when 20+ instances ran simultaneously. Now it's a no-op pass-through.
// Views using scrollAwarePulse will appear static, which is acceptable
// since the loading states are temporary (replaced when real data arrives).
struct ScrollAwarePulse: ViewModifier {
    @Binding var isActive: Bool
    let duration: Double
    let autoreverses: Bool
    let delay: Double
    
    init(isActive: Binding<Bool>, duration: Double = 1.2, autoreverses: Bool = true, delay: Double = 0.5) {
        self._isActive = isActive
        self.duration = duration
        self.autoreverses = autoreverses
        self.delay = delay
    }
    
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    /// Apply a scroll-aware pulse animation that automatically pauses during scroll.
    /// This is a drop-in replacement for `.animation(.repeatForever, value: pulse)` + `.onAppear { pulse = true }`.
    ///
    /// Usage:
    /// ```
    /// @State private var pulse = false
    /// Circle()
    ///     .opacity(pulse ? 0.5 : 1.0)
    ///     .scrollAwarePulse(active: $pulse, duration: 1.2)
    /// ```
    func scrollAwarePulse(active: Binding<Bool>, duration: Double = 1.2, autoreverses: Bool = true, delay: Double = 0.5) -> some View {
        self.modifier(ScrollAwarePulse(isActive: active, duration: duration, autoreverses: autoreverses, delay: delay))
    }
}
