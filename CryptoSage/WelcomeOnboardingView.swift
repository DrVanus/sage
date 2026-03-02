//
//  WelcomeOnboardingView.swift
//  CryptoSage
//
//  First-launch onboarding experience. 3-screen carousel introducing
//  the app's value proposition, core experience, and optional sign-in.
//  Designed to match the premium gold-on-black aesthetic.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn

// MARK: - Welcome Onboarding View

struct WelcomeOnboardingView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var authManager = AuthenticationManager.shared
    
    @State private var currentPage = 0
    @State private var appeared = false
    @State private var showEmailAuth = false
    @State private var isGoogleLoading = false
    private let totalPages = 3
    
    var body: some View {
        ZStack {
            DS.Adaptive.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    brandPage.tag(0)
                    experiencePage.tag(1)
                    accountPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)
                
                bottomControls
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                appeared = true
            }
        }
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: 14) {
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? BrandColors.goldBase : Color.white.opacity(0.18))
                        .frame(width: index == currentPage ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPage)
                }
            }
            .padding(.bottom, 2)
            
            if currentPage < totalPages - 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { currentPage += 1 }
                } label: {
                    Text("Continue")
                        .font(.body.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                }
                
                Button { dismissOnboarding() } label: {
                    Text("Skip")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.35))
                }
            } else {
                // Auth options — tighter spacing to fit 4 items
                VStack(spacing: 10) {
                // Apple Sign In (top, prominent — required by Apple guidelines)
                SignInWithAppleButton(
                    onRequest: { request in
                        authManager.prepareAppleSignInRequest(request)
                    },
                    onCompletion: { result in
                        authManager.handleAppleSignIn(result: result)
                        dismissOnboarding()
                    }
                )
                .signInWithAppleButtonStyle(.white)
                .frame(maxWidth: 375, minHeight: 48, maxHeight: 48)
                .cornerRadius(13)
                
                // Google Sign In
                Button(action: signInWithGoogleOnboarding) {
                    HStack(spacing: 10) {
                        if isGoogleLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 20, height: 20)
                                Text("G")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                            }
                            Text("Sign in with Google")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                    )
                }
                .disabled(isGoogleLoading)
                
                // Email Sign Up
                Button {
                    showEmailAuth = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14, weight: .medium))
                        Text("Sign up with Email")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                }
                .sheet(isPresented: $showEmailAuth) {
                    EmailAuthView()
                }
                } // end VStack(spacing: 10)
                
                Button { dismissOnboarding() } label: {
                    Text("Continue without account")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 36)
    }
    
    // MARK: - Page 1: Brand & Value Proposition
    
    private var brandPage: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Hero icon
            heroIcon(symbol: "wand.and.stars", glowColor: BrandColors.goldBase)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
            
            Spacer().frame(height: 28)
            
            VStack(spacing: 12) {
                Text("AI-Powered\nCrypto Intelligence")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                
                Text("Markets, portfolio, trading, and AI insights\n— everything you need in one app")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.50))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)
            
            Spacer().frame(height: 32)
            
            // Clean bullet points — no icons, professional tone
            VStack(spacing: 14) {
                bulletPoint("Intelligent AI that analyzes the crypto market for you")
                bulletPoint("Real-time prices, charts, and market data")
                bulletPoint("Practice trading risk-free with paper mode")
                bulletPoint("Free to use with optional premium features")
            }
            .padding(.horizontal, 36)
            
            Spacer()
        }
    }
    
    // MARK: - Page 2: The Experience (5 tabs)
    
    private var experiencePage: some View {
        VStack(spacing: 0) {
            Spacer()
            
            heroIcon(symbol: "square.grid.2x2.fill", glowColor: Color.blue)
            
            Spacer().frame(height: 32)
            
            VStack(spacing: 14) {
                Text("Everything in\nFive Taps")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                
                Text("Navigate the entire crypto market\nfrom five simple screens")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.50))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)
            
            Spacer().frame(height: 32)
            
            // The 5 tabs — visual map of the app
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    tabCard(icon: "house.fill", name: "Home", desc: "Dashboard & news")
                    tabCard(icon: "chart.line.uptrend.xyaxis", name: "Market", desc: "Prices & charts")
                }
                HStack(spacing: 8) {
                    tabCard(icon: "arrow.left.arrow.right", name: "Trade", desc: "Paper & live")
                    tabCard(icon: "chart.pie.fill", name: "Portfolio", desc: "Track everything")
                }
                HStack(spacing: 8) {
                    // AI tab — full width to emphasize it
                    tabCardWide(icon: "bubble.left.and.bubble.right.fill", name: "AI Chat", desc: "Ask anything about crypto — get instant analysis, predictions & trade ideas")
                }
            }
            .padding(.horizontal, 28)
            
            Spacer()
        }
    }
    
    // MARK: - Page 3: Account
    
    private var accountPage: some View {
        VStack(spacing: 0) {
            Spacer()
            
            heroIcon(symbol: "person.crop.circle.badge.checkmark", glowColor: Color.green)
                .scaleEffect(0.9)
            
            Spacer().frame(height: 20)
            
            VStack(spacing: 10) {
                Text("Get Started")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Create a free account to unlock sync,\nor continue without one")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.50))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)
            
            Spacer().frame(height: 20)
            
            VStack(spacing: 8) {
                benefitRow(icon: "arrow.triangle.2.circlepath", title: "Sync across devices", subtitle: "Access your portfolio anywhere")
                benefitRow(icon: "icloud.fill", title: "Cloud backups", subtitle: "Your data is safely stored")
                benefitRow(icon: "lock.fill", title: "Secure authentication", subtitle: "Industry-standard encryption")
            }
            .padding(.horizontal, 28)
            
            Spacer()
        }
    }
    
    // MARK: - Reusable Components
    
    /// Shared hero icon with glow ring
    private func heroIcon(symbol: String, glowColor: Color) -> some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [glowColor.opacity(0.12), Color.clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: 95
                    )
                )
                .frame(width: 190, height: 190)
            
            // Gold ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [BrandColors.goldLight.opacity(0.55), BrandColors.goldDark.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.8
                )
                .frame(width: 120, height: 120)
            
            // Dark inner fill
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.14), Color(white: 0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 116, height: 116)
            
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
    
    /// Clean bullet point (Page 1) — no icon, just a gold dot + text
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(BrandColors.goldBase)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
        }
    }
    
    /// Tab card (Page 2) — shows one of the 5 main tabs
    private func tabCard(icon: String, name: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BrandColors.goldBase)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
    
    /// Wide tab card for AI Chat emphasis
    private func tabCardWide(icon: String, name: String, desc: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BrandColors.goldBase.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(2)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BrandColors.goldBase.opacity(0.06), Color.white.opacity(0.03)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BrandColors.goldBase.opacity(0.12), lineWidth: 0.5)
                )
        )
    }
    
    /// Benefit row with checkmark (Page 3) — compact
    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(BrandColors.goldBase.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.40))
            }
            
            Spacer(minLength: 0)
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(BrandColors.goldBase.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Google Sign-In (Onboarding)
    
    private func signInWithGoogleOnboarding() {
        isGoogleLoading = true
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            isGoogleLoading = false
            return
        }
        
        var topVC = rootViewController
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: topVC) { result, error in
            isGoogleLoading = false
            
            if let error = error {
                let nsError = error as NSError
                if nsError.code == GIDSignInError.canceled.rawValue { return }
                print("[Onboarding] Google sign-in error: \(error.localizedDescription)")
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else { return }
            
            let accessToken = user.accessToken.tokenString
            
            Task {
                do {
                    try await authManager.signInWithGoogleCredential(
                        idToken: idToken,
                        accessToken: accessToken
                    )
                    await MainActor.run { dismissOnboarding() }
                } catch {
                    print("[Onboarding] Google Firebase auth failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func dismissOnboarding() {
        isPresented = false
    }
}
