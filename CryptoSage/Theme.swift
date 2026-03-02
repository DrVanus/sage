//
//  Theme.swift
//  CryptoSage
//
//  Created by YourName on 3/25/25.
//

import SwiftUI

/// A namespace for all shared colors used throughout the app.
struct Theme {
    // MARK: Backgrounds
    static let backgroundBlack = Color("backgroundBlack")  // e.g. #000000
    static let cardGray       = Color("cardGray")         // e.g. #1D1D1F (dark card color)

    // MARK: Accent Colors
    static let accentBlue     = Color("accentBlue")       // e.g. #007AFF (iOS default blue)
    static let primaryGreen   = Color("primaryGreen")     // e.g. #32D74B
    static let errorRed       = Color("errorRed")         // e.g. #FF3B30
    static let toggleOnColor  = Color("toggleOnColor")    // e.g. #34C759 (iOS green)

    // MARK: Text Colors
    static let buttonTextColor = Color.white
}

import SwiftUI
import Combine

// MARK: - AppTheme
enum AppTheme {
    // nil => system-based; .light => always light; .dark => always dark
    static var currentColorScheme: ColorScheme? = nil
}

// MARK: - ThemedRootView
/// A container that respects the current color scheme for navigation bar styling
/// and applies the app-wide preferred color scheme.
struct ThemedRootView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        
        // Use default system appearance - let color scheme handle light/dark
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        
        // Allow system to handle translucency properly
        UINavigationBar.appearance().isTranslucent = true
    }
    
    var body: some View {
        content
            .preferredColorScheme(AppTheme.currentColorScheme)
    }
}

// MARK: - FuturisticBackground
/// MEMORY FIX: Drastically simplified from 9 heavy layers to lightweight gradients only.
/// Previously, each instance created:
///   - A MetalPerlinNoiseView (MTKView with triple-buffered GPU textures = ~3 MB)
///   - AnimatedSparkleOverlay (12 animated circles with timers)
///   - InteractiveTouchOverlay (touch tracking + ripple animations)
///   - 6 layers with blend modes (.overlay, .lighten, .multiply, .plusLighter)
///     Each blend mode forces a SEPARATE offscreen render buffer at full screen resolution
///     (~14 MB per buffer on iPhone Pro Max = ~84 MB per FuturisticBackground instance)
///
/// With 27 views using FuturisticBackground, the GPU memory alone could exceed 500+ MB,
/// causing iOS to terminate the app with "too much memory."
///
/// This simplified version keeps the premium gradient feel while using ZERO offscreen
/// render buffers and ZERO GPU textures. The visual difference is subtle - just the
/// animated noise and sparkles are gone, but the gradient + wave pattern remain.
struct FuturisticBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    // Premium light mode colors
    private let lightBgTop = Color(red: 0.98, green: 0.98, blue: 0.97)      // Warm off-white
    private let lightBgBottom = Color(red: 0.94, green: 0.95, blue: 0.96)   // Cool light gray
    
    var body: some View {
        ZStack {
            if colorScheme == .light {
                // Light mode: clean, bright gradient with subtle warmth
                LinearGradient(
                    gradient: Gradient(colors: [
                        lightBgTop,
                        lightBgBottom
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            } else {
                // Dark mode: black -> subtle gray
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color.gray.opacity(0.3)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            
            // Radial highlight in the center - NO blend mode (avoids offscreen buffer)
            RadialGradient(
                gradient: Gradient(colors: [
                    colorScheme == .light 
                        ? Color.white.opacity(0.6) 
                        : Color.white.opacity(0.05),
                    Color.clear
                ]),
                center: .center,
                startRadius: 10,
                endRadius: 400
            )
            .ignoresSafeArea()

            // Keep texture subtle in light mode only; dark mode lines look like banding.
            if colorScheme == .light {
                WavePatternShape(lineCount: 8, amplitude: 6)
                    .stroke(Color.black.opacity(0.02), lineWidth: 0.8)
                    .ignoresSafeArea()
            }

            // Mode-specific overlay - NO blend mode
            if colorScheme == .dark {
                // Dark mode: darker top overlay to keep nav area black
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.9),
                        Color.clear
                    ]),
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            } else {
                // Light mode: subtle warm tint at bottom for depth
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color(red: 0.96, green: 0.94, blue: 0.90).opacity(0.3)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
        // NOTE: .drawingGroup() intentionally NOT used here - it creates a ~14 MB offscreen
        // buffer per instance, and FuturisticBackground is used in 24+ views. The simple
        // gradients here are lightweight enough for SwiftUI to composite directly.
    }
}

// MARK: - WavePatternShape
struct WavePatternShape: Shape {
    let lineCount: Int
    let amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<lineCount {
            let y = rect.height * CGFloat(i) / CGFloat(lineCount - 1)
            path.move(to: CGPoint(x: 0, y: y))
            path.addCurve(
                to: CGPoint(x: rect.width, y: y),
                control1: CGPoint(
                    x: rect.width * 0.3,
                    y: y + amplitude * sin(CGFloat(i))
                ),
                control2: CGPoint(
                    x: rect.width * 0.7,
                    y: y - amplitude * sin(CGFloat(i))
                )
            )
        }
        return path
    }
}

// MARK: - AnimatedSparkleOverlay
struct AnimatedSparkleOverlay: View {
    let sparkleCount: Int
    
    struct Sparkle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var offset: CGPoint
        var baseOpacity: Double
        var size: CGFloat
        var animationPhase: Double // Staggered animation timing
        var hasGoldTint: Bool
    }
    
    @State private var sparkles: [Sparkle] = []
    @State private var animateFlag = false
    @State private var containerSize: CGSize = .zero
    @State private var sparkleTimer: Timer? = nil
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(sparkles) { sp in
                    // Premium sparkle with subtle gold tint variation
                    ZStack {
                        // Outer glow (subtle)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        (sp.hasGoldTint ? BrandColors.goldBase : Color.white).opacity(0.3),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: sp.size * 2
                                )
                            )
                            .frame(width: sp.size * 4, height: sp.size * 4)
                        
                        // Core sparkle
                        Circle()
                            .fill(sp.hasGoldTint ? BrandColors.goldLight : Color.white)
                            .frame(width: sp.size, height: sp.size)
                    }
                    .position(
                        x: sp.position.x + (animateFlag ? sp.offset.x : -sp.offset.x),
                        y: sp.position.y + (animateFlag ? sp.offset.y : -sp.offset.y)
                    )
                    .opacity(animateFlag ? sp.baseOpacity : sp.baseOpacity * 0.2)
                    .scaleEffect(animateFlag ? 1.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 3 + sp.animationPhase)
                        .repeatForever(autoreverses: true)
                        .delay(sp.animationPhase),
                        value: animateFlag
                    )
                }
            }
            .onAppear {
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    containerSize = geo.size
                    generateSparkles()
                    
                    // Re-randomize sparkles every 10 seconds for subtle variation
                    sparkleTimer?.invalidate()
                    // TIMER LEAK FIX: Removed [self] strong capture. Added timer.isValid guard
                    // so the callback exits early if the timer was invalidated in onDisappear.
                    sparkleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { timer in
                        guard timer.isValid else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 3)) {
                                generateSparkles()
                            }
                        }
                    }
                    
                    // Trigger the animation
                    animateFlag = true
                }
            }
            .onDisappear {
                sparkleTimer?.invalidate()
                sparkleTimer = nil
            }
            .onChange(of: geo.size) { _, newSize in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    containerSize = newSize
                    generateSparkles()
                }
            }
        }
    }
    
    private func generateSparkles() {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return
        }
        sparkles = (0..<sparkleCount).map { index in
            let x = CGFloat.random(in: 0..<containerSize.width)
            let y = CGFloat.random(in: 0..<containerSize.height)
            let offX = CGFloat.random(in: -4...4)
            let offY = CGFloat.random(in: -4...4)
            let op = Double.random(in: 0.03...0.12)
            let size = CGFloat.random(in: 1.0...2.0)
            let phase = Double.random(in: 0...2) // Stagger animations
            let hasGold = index % 4 == 0 // Every 4th sparkle has gold tint
            
            return Sparkle(
                position: CGPoint(x: x, y: y),
                offset: CGPoint(x: offX, y: offY),
                baseOpacity: op,
                size: size,
                animationPhase: phase,
                hasGoldTint: hasGold
            )
        }
    }
}

// MARK: - InteractiveTouchOverlay
struct InteractiveTouchOverlay: View {
    var isDarkMode: Bool = true
    @State private var ripples: [Ripple] = []
    
    struct Ripple: Identifiable {
        let id = UUID()
        var position: CGPoint
        var radius: CGFloat = 0
        var opacity: Double = 0.4
    }
    
    private var rippleColor: Color {
        isDarkMode ? Color.white : Color.black.opacity(0.3)
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(ripples) { ripple in
                    Circle()
                        .fill(rippleColor.opacity(ripple.opacity))
                        .frame(width: ripple.radius * 2, height: ripple.radius * 2)
                        .position(ripple.position)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        addRipple(at: value.location)
                    }
            )
            // PERFORMANCE FIX v2: Reduce from 30fps to 10fps - ripple animations don't need high framerate
            // PERFORMANCE FIX v19: Changed .common to .default - timer pauses during scroll
            .onReceive(
                Timer.publish(every: 1.0 / 10.0, on: .main, in: .default).autoconnect()
            ) { _ in
                // Only process if there are ripples to animate
                guard !ripples.isEmpty else { return }
                // PERFORMANCE FIX: Skip ripple animation during scroll
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                updateRipples()
            }
        }
    }
    
    private func addRipple(at location: CGPoint) {
        ripples.append(Ripple(position: location))
    }
    
    private func updateRipples() {
        for i in 0..<ripples.count {
            // Adjusted for 30fps (larger increments)
            ripples[i].radius += 2.4
            ripples[i].opacity -= 0.014
        }
        ripples.removeAll { $0.opacity <= 0 }
    }
}

// MARK: - Theme Colors
struct ThemeColors {
    let background     = Color(.systemBackground)
    let accent         = Color.accentColor
    let secondary      = Color.secondary
    let cardBackground = Color(.secondarySystemBackground)
    let shadow         = Color.black

    /// Gradient start color for headers and cards
    let gradientStart = Color(red: 0.25, green: 0.35, blue: 0.75)  // #4059BF

    /// Gradient end color for headers and cards
    let gradientEnd   = Color(red: 0.10, green: 0.15, blue: 0.45)  // #1A2646
}

extension Color {
    static var theme: ThemeColors { ThemeColors() }
}
