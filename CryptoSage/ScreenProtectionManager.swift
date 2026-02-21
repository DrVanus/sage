//
//  ScreenProtectionManager.swift
//  CryptoSage
//
//  Screen protection for app switcher - used by Coinbase, Robinhood, Binance.
//  Adds a premium blur overlay when the app enters the background to protect sensitive data.
//

import SwiftUI
import UIKit

// MARK: - Screen Protection Manager

/// Manages screen protection by adding blur overlay when app goes to background.
/// This is a security standard used by all major financial apps.
final class ScreenProtectionManager: ObservableObject {
    static let shared = ScreenProtectionManager()
    
    // MEMORY FIX v8: Remove NotificationCenter observers on deallocation
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - State
    
    // PERFORMANCE FIX: Removed @Published to prevent SwiftUI re-renders when protection toggles.
    // No SwiftUI view needs to react to protection state changes - the UIKit blur window handles itself.
    private(set) var isProtectionActive: Bool = false
    
    // MARK: - Private Properties
    
    private var blurWindow: UIWindow?
    private var isSetup = false
    private let isRuntimeEnabled: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }()
    
    private init() {}
    
    // MARK: - Setup
    
    /// Call this once from the app's main entry point
    func setup() {
        guard !isSetup else { return }
        isSetup = true
        guard isRuntimeEnabled else {
            #if DEBUG
            print("🛡️ [ScreenProtection] Disabled on Simulator")
            #endif
            return
        }
        
        // Listen for app lifecycle events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        print("🛡️ [ScreenProtection] Initialized")
    }
    
    // MARK: - Lifecycle Handlers
    
    @objc private func appWillResignActive() {
        showProtection()
    }
    
    @objc private func appDidBecomeActive() {
        // Small delay to ensure smooth transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.hideProtection()
        }
    }
    
    @objc private func appDidEnterBackground() {
        showProtection()
    }
    
    // MARK: - Protection UI
    
    private func showProtection() {
        guard isRuntimeEnabled else { return }
        guard blurWindow == nil else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
            else { return }
            
            // Create blur window
            let window = UIWindow(windowScene: windowScene)
            window.windowLevel = .alert + 1
            window.backgroundColor = .clear
            
            // Create premium blur view controller
            let blurVC = PremiumScreenProtectionViewController()
            window.rootViewController = blurVC
            window.makeKeyAndVisible()
            
            self?.blurWindow = window
            self?.isProtectionActive = true
            
            #if DEBUG
            print("🛡️ [ScreenProtection] Protection activated")
            #endif
        }
    }
    
    private func hideProtection() {
        guard isRuntimeEnabled else { return }
        guard blurWindow != nil else { return }
        
        DispatchQueue.main.async { [weak self] in
            UIView.animate(withDuration: 0.2, animations: {
                self?.blurWindow?.alpha = 0
            }, completion: { _ in
                self?.blurWindow?.isHidden = true
                self?.blurWindow = nil
                self?.isProtectionActive = false
                
                #if DEBUG
                print("🛡️ [ScreenProtection] Protection deactivated")
                #endif
            })
        }
    }
    
    // MARK: - Manual Control
    
    /// Manually show protection (e.g., when displaying sensitive data)
    func forceShowProtection() {
        guard isRuntimeEnabled else { return }
        showProtection()
    }
    
    /// Manually hide protection
    func forceHideProtection() {
        guard isRuntimeEnabled else { return }
        hideProtection()
    }
}

// MARK: - Premium Screen Protection View Controller

/// Premium view controller that displays a branded security overlay matching CryptoSage AI's design system
private class PremiumScreenProtectionViewController: UIViewController {
    
    // MARK: - Brand Colors (matching BrandColors.swift)
    
    private let goldLight = UIColor(red: 243/255, green: 211/255, blue: 109/255, alpha: 1)  // #F3D36D
    private let goldBase = UIColor(red: 212/255, green: 175/255, blue: 55/255, alpha: 1)    // #D4AF37
    private let goldDark = UIColor(red: 140/255, green: 107/255, blue: 0/255, alpha: 1)     // #8C6B00
    
    // MARK: - Background Layers (stored for frame updates)
    private var backgroundGradientLayer: CAGradientLayer?
    private var radialGlowLayer: CAGradientLayer?
    private var lastGlowRingBounds: CGRect = .zero
    private var lastBadgeBounds: CGRect = .zero
    private var didStartLayerAnimations = false
    
    // MARK: - UI Components
    
    private lazy var blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let view = UIVisualEffectView(effect: blur)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var contentContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    // Shield with gradient - using SF Symbol properly
    private lazy var shieldImageView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 72, weight: .regular)
        let image = UIImage(systemName: "shield.fill", withConfiguration: config)
        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    // Lock icon on top of shield
    private lazy var lockImageView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        let image = UIImage(systemName: "lock.fill", withConfiguration: config)
        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor(red: 0.12, green: 0.10, blue: 0.06, alpha: 0.85)
        return imageView
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "CryptoSage AI"
        label.font = .systemFont(ofSize: 30, weight: .bold)
        label.textAlignment = .center
        return label
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Portfolio hidden"
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.45)
        label.textAlignment = .center
        return label
    }()
    
    private lazy var securityBadgeView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 18
        return view
    }()
    
    private lazy var securityIconView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = UIImage(systemName: "checkmark.shield.fill", withConfiguration: config)
        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = goldBase
        return imageView
    }()
    
    private lazy var securityTextLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Privacy Mode"
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = goldBase
        return label
    }()
    
    // Outer glow ring around shield
    private lazy var glowRingView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackground()
        setupUI()
        applyGradients()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update background layers to fill entire screen on all devices
        backgroundGradientLayer?.frame = view.bounds
        radialGlowLayer?.frame = view.bounds
        if glowRingView.bounds != lastGlowRingBounds {
            lastGlowRingBounds = glowRingView.bounds
            updateGlowRing()
        }
        if securityBadgeView.bounds != lastBadgeBounds {
            lastBadgeBounds = securityBadgeView.bounds
            updateBadgeGradient()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartLayerAnimations else { return }
        didStartLayerAnimations = true
        startAnimations()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        shieldImageView.layer.removeAnimation(forKey: "breathe")
        lockImageView.layer.removeAnimation(forKey: "breathe")
        glowRingView.layer.removeAnimation(forKey: "glowPulse")
        securityBadgeView.layer.sublayers?.forEach { $0.removeAllAnimations() }
        didStartLayerAnimations = false
    }
    
    // MARK: - Setup
    
    private func setupBackground() {
        // Dark gradient background
        // Main background gradient
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1).cgColor,
            UIColor(red: 0.06, green: 0.05, blue: 0.04, alpha: 1).cgColor,
            UIColor(red: 0.04, green: 0.03, blue: 0.02, alpha: 1).cgColor
        ]
        gradientLayer.locations = [0.0, 0.5, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.frame = view.bounds
        view.layer.addSublayer(gradientLayer)
        self.backgroundGradientLayer = gradientLayer
        
        // Blur overlay
        view.addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Radial gold glow in center
        let radialGlow = CAGradientLayer()
        radialGlow.type = .radial
        radialGlow.colors = [
            goldBase.withAlphaComponent(0.12).cgColor,
            goldBase.withAlphaComponent(0.05).cgColor,
            UIColor.clear.cgColor
        ]
        radialGlow.locations = [0.0, 0.4, 1.0]
        radialGlow.startPoint = CGPoint(x: 0.5, y: 0.4)
        radialGlow.endPoint = CGPoint(x: 1.0, y: 1.0)
        radialGlow.frame = view.bounds
        view.layer.addSublayer(radialGlow)
        self.radialGlowLayer = radialGlow
    }
    
    private func setupUI() {
        // Content container
        view.addSubview(contentContainerView)
        NSLayoutConstraint.activate([
            contentContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentContainerView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            contentContainerView.widthAnchor.constraint(equalTo: view.widthAnchor),
            contentContainerView.heightAnchor.constraint(equalToConstant: 320)
        ])
        
        // Glow ring (behind shield)
        contentContainerView.addSubview(glowRingView)
        NSLayoutConstraint.activate([
            glowRingView.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
            glowRingView.topAnchor.constraint(equalTo: contentContainerView.topAnchor, constant: 10),
            glowRingView.widthAnchor.constraint(equalToConstant: 130),
            glowRingView.heightAnchor.constraint(equalToConstant: 130)
        ])
        
        // Shield image
        contentContainerView.addSubview(shieldImageView)
        NSLayoutConstraint.activate([
            shieldImageView.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
            shieldImageView.topAnchor.constraint(equalTo: contentContainerView.topAnchor, constant: 20),
            shieldImageView.widthAnchor.constraint(equalToConstant: 90),
            shieldImageView.heightAnchor.constraint(equalToConstant: 100)
        ])
        
        // Lock icon centered on shield (slightly up)
        contentContainerView.addSubview(lockImageView)
        NSLayoutConstraint.activate([
            lockImageView.centerXAnchor.constraint(equalTo: shieldImageView.centerXAnchor),
            lockImageView.centerYAnchor.constraint(equalTo: shieldImageView.centerYAnchor, constant: -2),
            lockImageView.widthAnchor.constraint(equalToConstant: 32),
            lockImageView.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // Title
        contentContainerView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: shieldImageView.bottomAnchor, constant: 28)
        ])
        
        // Subtitle
        contentContainerView.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            subtitleLabel.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8)
        ])
        
        // Security badge
        contentContainerView.addSubview(securityBadgeView)
        NSLayoutConstraint.activate([
            securityBadgeView.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
            securityBadgeView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            securityBadgeView.heightAnchor.constraint(equalToConstant: 36)
        ])
        
        // Security badge content
        let badgeStack = UIStackView(arrangedSubviews: [securityIconView, securityTextLabel])
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        badgeStack.axis = .horizontal
        badgeStack.spacing = 8
        badgeStack.alignment = .center
        
        securityBadgeView.addSubview(badgeStack)
        NSLayoutConstraint.activate([
            badgeStack.leadingAnchor.constraint(equalTo: securityBadgeView.leadingAnchor, constant: 16),
            badgeStack.trailingAnchor.constraint(equalTo: securityBadgeView.trailingAnchor, constant: -16),
            badgeStack.centerYAnchor.constraint(equalTo: securityBadgeView.centerYAnchor),
            securityIconView.widthAnchor.constraint(equalToConstant: 16),
            securityIconView.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
    
    private func applyGradients() {
        // Apply gold gradient to shield
        applyGoldGradientToImageView(shieldImageView)
        
        // Apply gold gradient to title
        applyGoldGradientToLabel(titleLabel)
    }
    
    private func updateGlowRing() {
        glowRingView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        let size = glowRingView.bounds.size
        guard size.width > 0 else { return }
        
        // Outer glow
        let glowLayer = CAGradientLayer()
        glowLayer.type = .radial
        glowLayer.colors = [
            goldBase.withAlphaComponent(0.35).cgColor,
            goldBase.withAlphaComponent(0.15).cgColor,
            goldBase.withAlphaComponent(0.05).cgColor,
            UIColor.clear.cgColor
        ]
        glowLayer.locations = [0.0, 0.3, 0.6, 1.0]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        glowLayer.frame = glowRingView.bounds
        glowRingView.layer.addSublayer(glowLayer)
        
        // Ring stroke
        let ringLayer = CAShapeLayer()
        let ringPath = UIBezierPath(ovalIn: glowRingView.bounds.insetBy(dx: 15, dy: 15))
        ringLayer.path = ringPath.cgPath
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = goldBase.withAlphaComponent(0.25).cgColor
        ringLayer.lineWidth = 1.5
        glowRingView.layer.addSublayer(ringLayer)
    }
    
    private func updateBadgeGradient() {
        securityBadgeView.layer.sublayers?.filter { $0 is CAGradientLayer }.forEach { $0.removeFromSuperlayer() }
        
        guard securityBadgeView.bounds.width > 0 else { return }
        
        // Glass effect background
        let glassLayer = CAGradientLayer()
        glassLayer.colors = [
            UIColor.white.withAlphaComponent(0.08).cgColor,
            UIColor.white.withAlphaComponent(0.03).cgColor
        ]
        glassLayer.locations = [0.0, 1.0]
        glassLayer.startPoint = CGPoint(x: 0.5, y: 0)
        glassLayer.endPoint = CGPoint(x: 0.5, y: 1)
        glassLayer.frame = securityBadgeView.bounds
        glassLayer.cornerRadius = 18
        securityBadgeView.layer.insertSublayer(glassLayer, at: 0)
        
        // Border
        securityBadgeView.layer.borderWidth = 1
        securityBadgeView.layer.borderColor = goldBase.withAlphaComponent(0.35).cgColor
    }
    
    private func applyGoldGradientToImageView(_ imageView: UIImageView) {
        guard imageView.image != nil else { return }
        
        let size = CGSize(width: 90, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let gradientImage = renderer.image { context in
            // Create gradient
            let colors = [goldLight.cgColor, goldBase.cgColor, goldDark.cgColor]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0.0, 0.5, 1.0]
            
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else { return }
            
            // Draw gradient
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }
        
        // Use gradient as pattern and mask with the symbol
        imageView.tintColor = UIColor(patternImage: gradientImage)
        
        // Add shadow for depth
        imageView.layer.shadowColor = goldBase.cgColor
        imageView.layer.shadowOffset = CGSize(width: 0, height: 6)
        imageView.layer.shadowRadius = 20
        imageView.layer.shadowOpacity = 0.5
    }
    
    private func applyGoldGradientToLabel(_ label: UILabel) {
        guard let text = label.text, let font = label.font else { return }
        
        let size = (text as NSString).size(withAttributes: [.font: font])
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let gradientImage = renderer.image { context in
            let colors = [goldLight.cgColor, goldBase.cgColor, goldDark.cgColor]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0.0, 0.5, 1.0]
            
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else { return }
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }
        
        label.textColor = UIColor(patternImage: gradientImage)
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        // Subtle breathing animation on shield
        let breatheAnimation = CABasicAnimation(keyPath: "transform.scale")
        breatheAnimation.duration = 2.5
        breatheAnimation.fromValue = 1.0
        breatheAnimation.toValue = 1.04
        breatheAnimation.autoreverses = true
        breatheAnimation.repeatCount = .infinity
        breatheAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shieldImageView.layer.add(breatheAnimation, forKey: "breathe")
        lockImageView.layer.add(breatheAnimation, forKey: "breathe")
        
        // Glow pulse animation
        let glowPulse = CABasicAnimation(keyPath: "opacity")
        glowPulse.duration = 2.0
        glowPulse.fromValue = 0.7
        glowPulse.toValue = 1.0
        glowPulse.autoreverses = true
        glowPulse.repeatCount = .infinity
        glowPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowRingView.layer.add(glowPulse, forKey: "glowPulse")
        
        // Subtle shimmer on badge
        animateBadgeShimmer()
    }
    
    private func animateBadgeShimmer() {
        let shimmerLayer = CAGradientLayer()
        shimmerLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.15).cgColor,
            UIColor.clear.cgColor
        ]
        shimmerLayer.locations = [0.0, 0.5, 1.0]
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerLayer.frame = CGRect(x: -securityBadgeView.bounds.width, y: 0, width: securityBadgeView.bounds.width * 2, height: securityBadgeView.bounds.height)
        shimmerLayer.cornerRadius = 18
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath(roundedRect: securityBadgeView.bounds, cornerRadius: 18).cgPath
        securityBadgeView.layer.mask = maskLayer
        securityBadgeView.layer.addSublayer(shimmerLayer)
        
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.duration = 3.0
        animation.fromValue = -securityBadgeView.bounds.width
        animation.toValue = securityBadgeView.bounds.width * 2
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmerLayer.add(animation, forKey: "shimmer")
    }
}

// MARK: - SwiftUI Integration

/// SwiftUI view modifier for screen protection
struct ScreenProtectionModifier: ViewModifier {
    @ObservedObject private var manager = ScreenProtectionManager.shared
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                manager.setup()
            }
    }
}

extension View {
    /// Enables screen protection for the app
    func withScreenProtection() -> some View {
        modifier(ScreenProtectionModifier())
    }
}
