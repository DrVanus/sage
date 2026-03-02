//
//  LockScreenView.swift
//  CryptoSage
//
//  Lock screen displayed when biometric authentication is required.
//

import SwiftUI

struct LockScreenView: View {
    @ObservedObject var authManager = BiometricAuthManager.shared
    @ObservedObject var pinManager = PINAuthManager.shared
    
    @State private var isAuthenticating = false
    @State private var logoScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.5
    @State private var showPINEntry = false
    
    var body: some View {
        // LAYOUT FIX: Use GeometryReader to ensure full screen coverage
        // without interfering with underlying safe area calculations
        GeometryReader { geometry in
            ZStack {
                // Background - explicit frame ensures no safe area interference
                DS.Adaptive.background
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                // Ambient glow
                RadialGradient(
                    gradient: Gradient(colors: [
                        BrandColors.goldBase.opacity(glowOpacity * 0.4),
                        BrandColors.goldBase.opacity(glowOpacity * 0.15),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 60,
                    endRadius: 250
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                
                if showPINEntry {
                    // PIN entry view
                    PINEntryView(mode: .verify) { success in
                        if success {
                            authManager.isLocked = false
                            let notification = UINotificationFeedbackGenerator()
                            notification.notificationOccurred(.success)
                        }
                        showPINEntry = false
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Main lock screen
                    mainLockContent
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // LAYOUT FIX: Ignore all safe areas to prevent interference with underlying views
        .ignoresSafeArea(.all)
        .preferredColorScheme(.dark)
        .onAppear {
            startAnimations()
            // Auto-trigger biometric authentication on appear (only if biometric is available)
            if authManager.canUseBiometric && authManager.isBiometricEnabled {
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                    await authenticateUser()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showPINEntry)
    }
    
    private var mainLockContent: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Lock icon with biometric type
            ZStack {
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .stroke(BrandColors.goldBase.opacity(0.4), lineWidth: 2)
                    .frame(width: 120, height: 120)
                
                Image(systemName: authManager.biometricType.iconName)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(BrandColors.goldBase)
                    .scaleEffect(logoScale)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("CryptoSage locked, \(authManager.biometricType.displayName) authentication")
            .accessibilityAddTraits(.isImage)
            
            // Title
            VStack(spacing: 8) {
                Text("CryptoSage Locked")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                
                if authManager.canUseBiometric {
                    Text("Use \(authManager.biometricType.displayName) to unlock")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else if authManager.canUsePINFallback {
                    Text("Enter your PIN to unlock")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    Text("Use your device passcode to unlock")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            // Error message if any
            if let error = authManager.authError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                // Primary unlock button (Biometric or Device Passcode)
                if authManager.canUseDeviceAuth {
                    Button(action: {
                        Task {
                            await authenticateUser()
                        }
                    }) {
                        HStack(spacing: 12) {
                            if isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: authManager.biometricType.iconName)
                                    .font(.system(size: 20, weight: .medium))
                            }
                            
                            Text(isAuthenticating ? "Authenticating..." : "Unlock with \(authManager.biometricType.displayName)")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [BrandColors.goldBase, BrandColors.goldBase.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    .disabled(isAuthenticating)
                    .accessibilityLabel(isAuthenticating ? "Authenticating" : "Unlock with \(authManager.biometricType.displayName)")
                    .accessibilityHint("Double tap to authenticate using \(authManager.biometricType.displayName)")
                }

                // PIN fallback button (if PIN is set up)
                if authManager.canUsePINFallback {
                    Button(action: {
                        showPINEntry = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.grid.3x3")
                                .font(.system(size: 16, weight: .medium))
                            Text("Use PIN")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundColor(BrandColors.goldBase)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BrandColors.goldBase.opacity(0.5), lineWidth: 1)
                        )
                    }
                    .accessibilityLabel("Use PIN")
                    .accessibilityHint("Double tap to enter your PIN code")
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
    }
    
    private func authenticateUser() async {
        guard !isAuthenticating else { return }
        
        isAuthenticating = true
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        let success = await authManager.authenticate()
        
        isAuthenticating = false
        
        if success {
            // Success haptic
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
        }
    }
    
    private func startAnimations() {
        // Gentle pulse animation
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            logoScale = 1.05
            glowOpacity = 0.7
        }
    }
}

// MARK: - Preview

#Preview {
    LockScreenView()
}
