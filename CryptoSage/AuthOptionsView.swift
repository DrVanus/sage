//
//  AuthOptionsView.swift
//  CryptoSage
//
//  Unified authentication options sheet showing
//  Apple Sign-In, Google Sign-In, and Email auth.
//  Presentable as a .sheet from anywhere in the app.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn
import FirebaseAuth

// MARK: - Auth Options View

struct AuthOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var authManager = AuthenticationManager.shared
    
    @State private var showEmailAuth = false
    @State private var isGoogleLoading = false
    @State private var errorMessage: String? = nil
    
    /// Optional: show "Continue without account" link
    var showSkipOption: Bool = false
    var onSkip: (() -> Void)? = nil
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer().frame(height: 40)
                
                // Logo / branding
                VStack(spacing: 14) {
                    // Shield icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.goldBase.opacity(0.2), BrandColors.goldBase.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                        
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    
                    Text("Sign in to CryptoSage")
                        .font(.title2.weight(.bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text("Sync your data across devices, unlock premium features, and keep your portfolio secure.")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .lineSpacing(2)
                }
                .padding(.bottom, 36)
                
                // Auth buttons
                VStack(spacing: 12) {
                    // MARK: Apple Sign In
                    // Per Apple HIG: use .white in dark mode, .black in light mode
                    // Don't clip the corner radius — let Apple control its own rendering
                    SignInWithAppleButton(.signIn) { request in
                        authManager.prepareAppleSignInRequest(request)
                    } onCompletion: { result in
                        authManager.handleAppleSignIn(result: result)
                        if case .signedIn = authManager.state {
                            dismiss()
                        }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .cornerRadius(12)
                    
                    // MARK: Google Sign In
                    // Per Google branding: use proper multicolor "G" logo, white/dark button
                    Button(action: signInWithGoogle) {
                        HStack(spacing: 10) {
                            if isGoogleLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: DS.Adaptive.textPrimary))
                                    .frame(width: 20, height: 20)
                            } else {
                                // Google multicolor "G" logo
                                googleLogo
                                    .frame(width: 20, height: 20)
                            }
                            Text("Sign in with Google")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colorScheme == .dark
                                      ? Color.white.opacity(0.08)
                                      : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(colorScheme == .dark
                                        ? Color.white.opacity(0.15)
                                        : Color.black.opacity(0.12),
                                        lineWidth: 1)
                        )
                    }
                    .disabled(isGoogleLoading)
                    .buttonStyle(.plain)
                    
                    // Divider
                    HStack(spacing: 16) {
                        Rectangle()
                            .fill(DS.Adaptive.stroke)
                            .frame(height: 0.5)
                        Text("or")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Rectangle()
                            .fill(DS.Adaptive.stroke)
                            .frame(height: 0.5)
                    }
                    .padding(.vertical, 6)
                    
                    // MARK: Email
                    Button {
                        impactLight.impactOccurred()
                        showEmailAuth = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 15, weight: .medium))
                            Text("Continue with Email")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                
                // Error message
                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
                
                Spacer()
                
                // Skip option
                if showSkipOption {
                    Button {
                        impactLight.impactOccurred()
                        onSkip?()
                        dismiss()
                    } label: {
                        Text("Continue without account")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(.bottom, 12)
                }
                
                // Terms — make "Terms of Service" and "Privacy Policy" tappable
                Text("By signing in, you agree to our Terms of Service and Privacy Policy.")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                DS.Adaptive.textTertiary,
                                DS.Adaptive.cardBackground
                            )
                    }
                }
            }
            .sheet(isPresented: $showEmailAuth) {
                EmailAuthView()
            }
            .onChange(of: authManager.isAuthenticated) { _, isAuth in
                if isAuth {
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Google Logo
    /// Google "G" on a white pill — matches the standard pattern used by
    /// Coinbase, Robinhood, Cash App, and other production iOS apps.
    @ViewBuilder
    private var googleLogo: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 22, height: 22)
            
            // Official Google blue
            Text("G")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
        }
    }
    
    // MARK: - Google Sign-In
    
    private func signInWithGoogle() {
        impactLight.impactOccurred()
        isGoogleLoading = true
        errorMessage = nil
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to present Google Sign-In."
            isGoogleLoading = false
            return
        }
        
        // Find the topmost presented view controller
        var topVC = rootViewController
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: topVC) { [self] result, error in
            isGoogleLoading = false
            
            if let error = error {
                // Don't show error for user cancellation
                let nsError = error as NSError
                if nsError.code == GIDSignInError.canceled.rawValue {
                    return
                }
                errorMessage = error.localizedDescription
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                errorMessage = "Unable to get Google credentials."
                return
            }
            
            let accessToken = user.accessToken.tokenString
            
            Task {
                do {
                    try await authManager.signInWithGoogleCredential(
                        idToken: idToken,
                        accessToken: accessToken
                    )
                    // dismiss handled by onChange
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
