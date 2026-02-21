//
//  EdgeSwipeDismissModifier.swift
//  CryptoSage
//
//  A ViewModifier that adds left-edge swipe gesture for dismissing views.
//  Works on sheets, fullScreenCover, and navigation-pushed views.
//
//  Also includes InteractivePopGestureEnabler which re-enables the native
//  iOS interactive pop gesture when the back button is hidden.
//

import SwiftUI
import UIKit

// MARK: - Native Pop Preference Environment

private struct PrefersNativePopGestureKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private extension EnvironmentValues {
    var prefersNativePopGesture: Bool {
        get { self[PrefersNativePopGestureKey.self] }
        set { self[PrefersNativePopGestureKey.self] = newValue }
    }
}

// MARK: - Native Interactive Pop Gesture Enabler

/// A UIViewRepresentable that re-enables the native iOS interactive pop gesture
/// even when the navigation bar back button is hidden.
///
/// Uses UIView + responder chain traversal instead of UIViewControllerRepresentable,
/// which is more reliable in SwiftUI's NavigationStack hierarchy where the
/// UIViewControllerRepresentable's controller may not have a direct .navigationController.
struct InteractivePopGestureEnabler: UIViewRepresentable {
    func makeUIView(context: Context) -> InteractivePopGestureView {
        InteractivePopGestureView()
    }
    
    func updateUIView(_ uiView: InteractivePopGestureView, context: Context) {}
}

/// UIView that traverses the responder chain to find and enable the
/// UINavigationController's interactive pop gesture recognizer.
class InteractivePopGestureView: UIView {
    private var hasEnabled = false
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        enablePopGesture()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Retry on layout in case the nav controller wasn't available yet
        if !hasEnabled {
            enablePopGesture()
        }
    }
    
    private func enablePopGesture() {
        guard let nav = findNavigationController() else {
            // Retry on next run loop — avoids race while keeping interactions responsive.
            if !hasEnabled {
                DispatchQueue.main.async { [weak self] in
                    self?.enablePopGesture()
                }
            }
            return
        }
        if let popGesture = nav.interactivePopGestureRecognizer {
            popGesture.isEnabled = true
            // SwiftUI sometimes leaves a delegate that blocks begin when custom
            // back buttons are used. Reset to restore native edge-pop behavior.
            popGesture.delegate = nil
            hasEnabled = true
        }
    }
    
    /// Traverse the responder chain to find the nearest UINavigationController.
    /// The responder chain includes UIViewControllers, making this more reliable
    /// than UIViewController.navigationController in SwiftUI hierarchies.
    private func findNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let nav = next as? UINavigationController {
                return nav
            }
            responder = next
        }
        // Fallback: locate the visible navigation controller from window hierarchy.
        if let root = window?.rootViewController {
            return Self.findNavigationController(in: root)
        }
        return nil
    }

    private static func findNavigationController(in vc: UIViewController) -> UINavigationController? {
        if let nav = vc as? UINavigationController { return nav }
        for child in vc.children {
            if let found = findNavigationController(in: child) { return found }
        }
        if let presented = vc.presentedViewController {
            if let found = findNavigationController(in: presented) { return found }
        }
        return nil
    }
}

// MARK: - Native Pop Availability Probe

/// Detects whether the current view is inside a navigation stack where the native
/// interactive-pop gesture should be the single source of truth.
private struct NativePopAvailabilityProbe: UIViewRepresentable {
    @Binding var isAvailable: Bool

    func makeUIView(context: Context) -> NativePopAvailabilityView {
        let view = NativePopAvailabilityView()
        view.onUpdate = { available in
            DispatchQueue.main.async {
                if isAvailable != available {
                    isAvailable = available
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: NativePopAvailabilityView, context: Context) {
        uiView.onUpdate = { available in
            DispatchQueue.main.async {
                if isAvailable != available {
                    isAvailable = available
                }
            }
        }
        uiView.refreshAvailability()
    }
}

private final class NativePopAvailabilityView: UIView {
    var onUpdate: ((Bool) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshAvailability()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshAvailability()
    }

    func refreshAvailability() {
        guard let nav = findNavigationController() else {
            onUpdate?(false)
            return
        }
        let hasBackStack = nav.viewControllers.count > 1
        let popEnabled = nav.interactivePopGestureRecognizer?.isEnabled ?? false
        onUpdate?(hasBackStack && popEnabled)
    }

    private func findNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let nav = next as? UINavigationController {
                return nav
            }
            responder = next
        }
        if let root = window?.rootViewController {
            return Self.findNavigationController(in: root)
        }
        return nil
    }

    private static func findNavigationController(in vc: UIViewController) -> UINavigationController? {
        if let nav = vc as? UINavigationController { return nav }
        for child in vc.children {
            if let found = findNavigationController(in: child) { return found }
        }
        if let presented = vc.presentedViewController {
            if let found = findNavigationController(in: presented) { return found }
        }
        return nil
    }
}

// MARK: - View Extension for Native Pop Gesture

extension View {
    /// Enables the native iOS interactive pop gesture (swipe from left edge to go back)
    /// even when the navigation bar back button is hidden.
    /// 
    /// This provides the most native swipe-back experience and should be applied to
    /// any view that hides the back button but should still support swipe-to-go-back.
    ///
    /// Usage:
    /// ```swift
    /// SomeDetailView()
    ///     .navigationBarBackButtonHidden(true)
    ///     .enableInteractivePopGesture()
    /// ```
    func enableInteractivePopGesture() -> some View {
        self
            .background(InteractivePopGestureEnabler())
            .environment(\.prefersNativePopGesture, true)
    }
    
    /// Convenience modifier that combines hiding the back button with enabling the
    /// interactive pop gesture. Use this instead of calling both separately.
    ///
    /// Usage:
    /// ```swift
    /// SomeDetailView()
    ///     .customBackButtonWithSwipe()
    /// ```
    func customBackButtonWithSwipe() -> some View {
        self
            .navigationBarBackButtonHidden(true)
            .background(InteractivePopGestureEnabler())
    }
}

// MARK: - Edge Swipe Dismiss Modifier

/// A view modifier that adds an interactive left-edge swipe gesture for dismissing views.
/// Mimics iOS native navigation swipe-back behavior.
///
/// Uses `.simultaneousGesture()` so the edge swipe works alongside child gestures
/// (List onMove, ScrollView, etc.) instead of being preempted by them.
struct EdgeSwipeDismissModifier: ViewModifier {
    /// The dismiss action to call when swipe completes
    var onDismiss: () -> Void
    
    /// Minimum swipe distance to trigger dismiss (default: 80 points)
    var minimumDistance: CGFloat = 80
    
    /// Whether to only respond to edge swipes (from left edge zone of screen)
    var edgeOnly: Bool = true
    
    /// Edge zone width for edge-only mode (44pt matches Apple HIG touch target)
    var edgeZoneWidth: CGFloat = 44
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @GestureState private var gestureState: CGFloat = 0
    @State private var nativePopIsAvailable: Bool = false
    @Environment(\.prefersNativePopGesture) private var prefersNativePopGesture
    
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            // If caller explicitly requests native pop, never run the custom page-offset
            // swipe animation. This avoids the dark "ghost" panel while dragging back.
            let useCustomSwipe = !nativePopIsAvailable
            let showInteractiveOffset = useCustomSwipe && !prefersNativePopGesture

            let base = ZStack {
                if showInteractiveOffset {
                    content
                        .offset(x: dragOffset)
                        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.85), value: dragOffset)

                    // Left edge drag indicator (subtle visual feedback)
                    if isDragging && dragOffset > 20 {
                        HStack {
                            EdgeSwipeIndicator(progress: min(1, dragOffset / minimumDistance))
                            Spacer()
                        }
                        .transition(.opacity)
                    }
                } else {
                    content
                }
            }
            .background(NativePopAvailabilityProbe(isAvailable: $nativePopIsAvailable))
            .background(InteractivePopGestureEnabler())

            if useCustomSwipe {
                if edgeOnly {
                    base.overlay(alignment: .leading) {
                        // Keep custom back swipe constrained to left-edge hit area so
                        // vertical scrolling in content cannot fight the dismiss gesture.
                        Color.clear
                            .frame(width: max(24, edgeZoneWidth + 6))
                            .contentShape(Rectangle())
                            .highPriorityGesture(customEdgeSwipeGesture(in: geometry, enabled: true))
                    }
                } else {
                    base.highPriorityGesture(customEdgeSwipeGesture(in: geometry, enabled: true))
                }
            } else {
                base
            }
        }
    }

    private func customEdgeSwipeGesture(in geometry: GeometryProxy, enabled: Bool) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .updating($gestureState) { value, state, _ in
                guard enabled else { return }
                let startX = value.startLocation.x
                let isFromEdge = !edgeOnly || startX < edgeZoneWidth
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.25
                let isRightward = value.translation.width > 6

                if isFromEdge && isHorizontal && isRightward {
                    state = value.translation.width
                }
            }
            .onChanged { value in
                guard enabled else { return }
                let startX = value.startLocation.x
                let isFromEdge = !edgeOnly || startX < edgeZoneWidth
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.25
                let isRightward = value.translation.width > 6

                if isFromEdge && isHorizontal && isRightward {
                    isDragging = true
                    let progress = value.translation.width / geometry.size.width
                    let resistance = 1 - (progress * 0.3)
                    dragOffset = value.translation.width * resistance
                }
            }
            .onEnded { value in
                guard enabled else {
                    dragOffset = 0
                    isDragging = false
                    return
                }
                let velocity = value.predictedEndTranslation.width - value.translation.width
                let shouldDismiss = dragOffset > minimumDistance || velocity > 500

                if shouldDismiss {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()

                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = geometry.size.width
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDismiss()
                    }
                } else {
                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }

                isDragging = false
            }
    }
}

// MARK: - Edge Swipe Indicator

/// A subtle visual indicator shown during edge swipe
private struct EdgeSwipeIndicator: View {
    let progress: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [
                        BrandColors.goldBase.opacity(0.6 * progress),
                        BrandColors.goldBase.opacity(0.2 * progress)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 4, height: 80)
            .padding(.leading, 4)
            .opacity(Double(progress))
    }
}

// MARK: - View Extension

extension View {
    /// Adds an interactive left-edge swipe gesture for dismissing the view.
    /// - Parameters:
    ///   - minimumDistance: Minimum swipe distance to trigger dismiss (default: 80)
    ///   - edgeOnly: Whether to only respond to swipes starting from the left edge (default: true)
    ///   - onDismiss: Action to perform when swipe completes
    /// - Returns: A view with the swipe-to-dismiss gesture attached
    func edgeSwipeToDismiss(
        minimumDistance: CGFloat = 80,
        edgeOnly: Bool = true,
        onDismiss: @escaping () -> Void
    ) -> some View {
        self.modifier(EdgeSwipeDismissModifier(
            onDismiss: onDismiss,
            minimumDistance: minimumDistance,
            edgeOnly: edgeOnly
        ))
    }
    
    /// Adds an interactive left-edge swipe gesture that calls the environment dismiss action.
    /// Convenience method for views using @Environment(\.dismiss).
    /// - Parameters:
    ///   - dismiss: The dismiss environment action
    ///   - minimumDistance: Minimum swipe distance to trigger dismiss (default: 80)
    ///   - edgeOnly: Whether to only respond to swipes starting from the left edge (default: true)
    /// - Returns: A view with the swipe-to-dismiss gesture attached
    func edgeSwipeToDismiss(
        dismiss: DismissAction,
        minimumDistance: CGFloat = 80,
        edgeOnly: Bool = true
    ) -> some View {
        self.modifier(EdgeSwipeDismissModifier(
            onDismiss: { dismiss() },
            minimumDistance: minimumDistance,
            edgeOnly: edgeOnly
        ))
    }
}

// MARK: - Simple Swipe Gesture (Non-Interactive)

/// A simpler swipe gesture for views that don't need interactive feedback.
/// Use this for sheets where the standard sheet swipe-down is disabled.
struct SimpleEdgeSwipeModifier: ViewModifier {
    var onDismiss: () -> Void
    var minimumDistance: CGFloat = 80
    
    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        // Only respond to rightward swipes from left portion of screen
                        let isFromLeftEdge = value.startLocation.x < 50
                        let isRightward = value.translation.width > minimumDistance
                        let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                        
                        if isFromLeftEdge && isRightward && isHorizontal {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onDismiss()
                        }
                    }
            )
    }
}

extension View {
    /// Adds a simple (non-interactive) left-edge swipe gesture for dismissing.
    /// Use this when you don't need the sliding animation feedback.
    func simpleEdgeSwipeToDismiss(
        minimumDistance: CGFloat = 80,
        onDismiss: @escaping () -> Void
    ) -> some View {
        self.modifier(SimpleEdgeSwipeModifier(
            onDismiss: onDismiss,
            minimumDistance: minimumDistance
        ))
    }
    
    /// Conditionally adds edge swipe dismiss - useful for views that can be both main tabs and subpages.
    /// - Parameters:
    ///   - enabled: Whether to enable the edge swipe (e.g., showBackButton)
    ///   - onDismiss: Action to perform when swipe completes
    @ViewBuilder
    func edgeSwipeToDismissIf(
        _ enabled: Bool,
        onDismiss: @escaping () -> Void
    ) -> some View {
        if enabled {
            self.modifier(EdgeSwipeDismissModifier(onDismiss: onDismiss))
        } else {
            self
        }
    }
    
    /// Complete detail page navigation setup: hides back button and enables both native
    /// iOS pop gesture AND the custom edge swipe with visual feedback.
    ///
    /// Use this for detail pages that need a custom navigation bar but should still
    /// support swipe-to-go-back.
    ///
    /// Usage:
    /// ```swift
    /// DetailView()
    ///     .detailPageNavigation(onDismiss: { dismiss() })
    ///     .toolbar { CustomToolbar(onBack: { dismiss() }) }
    /// ```
    func detailPageNavigation(onDismiss: @escaping () -> Void) -> some View {
        self
            .navigationBarBackButtonHidden(true)
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: onDismiss)
    }
    
    /// Complete detail page navigation setup using environment dismiss action.
    ///
    /// Usage:
    /// ```swift
    /// DetailView()
    ///     .detailPageNavigation(dismiss: dismiss)
    ///     .toolbar { CustomToolbar(onBack: { dismiss() }) }
    /// ```
    func detailPageNavigation(dismiss: DismissAction) -> some View {
        self
            .navigationBarBackButtonHidden(true)
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
}

// MARK: - Preview

#Preview("Edge Swipe Demo") {
    struct DemoView: View {
        @State private var showSheet = false
        @State private var showFullScreen = false
        
        var body: some View {
            VStack(spacing: 20) {
                Button("Show Sheet") { showSheet = true }
                Button("Show Full Screen") { showFullScreen = true }
            }
            .sheet(isPresented: $showSheet) {
                DemoSubpage(title: "Sheet View") {
                    showSheet = false
                }
            }
            .fullScreenCover(isPresented: $showFullScreen) {
                DemoSubpage(title: "Full Screen View") {
                    showFullScreen = false
                }
            }
        }
    }
    
    struct DemoSubpage: View {
        let title: String
        let onDismiss: () -> Void
        
        var body: some View {
            VStack {
                SubpageHeaderBar(
                    title: title,
                    showCloseButton: true,
                    onDismiss: onDismiss
                )
                
                Spacer()
                
                Text("Swipe from left edge to dismiss")
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .background(DS.Adaptive.background)
            .edgeSwipeToDismiss(onDismiss: onDismiss)
        }
    }
    
    return DemoView()
        .preferredColorScheme(.dark)
}
