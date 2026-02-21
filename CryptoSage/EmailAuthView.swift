//
//  EmailAuthView.swift
//  CryptoSage
//
//  Email sign-in and sign-up form with validation,
//  password reset, and the app's gold-on-dark design system.
//

import SwiftUI

// MARK: - Email Auth View

struct EmailAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authManager = AuthenticationManager.shared
    
    enum AuthMode: String, CaseIterable {
        case signIn = "Sign In"
        case signUp = "Create Account"
    }
    
    @State private var mode: AuthMode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var displayName: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showResetPassword: Bool = false
    @State private var resetEmail: String = ""
    @State private var resetSent: Bool = false
    @State private var showPassword: Bool = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case displayName, email, password, confirmPassword
    }
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Mode picker
                    Picker("", selection: $mode) {
                        ForEach(AuthMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                    .onChange(of: mode) { _, _ in
                        errorMessage = nil
                    }
                    
                    // Form fields
                    VStack(spacing: 16) {
                        // Display Name (sign-up only)
                        if mode == .signUp {
                            authField(
                                title: "Display Name",
                                icon: "person.fill",
                                text: $displayName,
                                placeholder: "Your name",
                                field: .displayName,
                                keyboardType: .default,
                                contentType: .name,
                                autocapitalization: .words
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        // Email
                        authField(
                            title: "Email",
                            icon: "envelope.fill",
                            text: $email,
                            placeholder: "email@example.com",
                            field: .email,
                            keyboardType: .emailAddress,
                            contentType: .emailAddress,
                            autocapitalization: .never
                        )
                        
                        // Password
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.caption.weight(.medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            
                            HStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(BrandColors.goldBase)
                                    .frame(width: 20)
                                
                                Group {
                                    if showPassword {
                                        TextField("Min. 6 characters", text: $password)
                                    } else {
                                        SecureField("Min. 6 characters", text: $password)
                                    }
                                }
                                .font(.body)
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .textContentType(mode == .signUp ? .newPassword : .password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .password)
                                
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(DS.Adaptive.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(
                                                focusedField == .password ? BrandColors.goldBase : DS.Adaptive.stroke,
                                                lineWidth: focusedField == .password ? 1.5 : 0.5
                                            )
                                    )
                            )
                        }
                        
                        // Confirm Password (sign-up only)
                        if mode == .signUp {
                            authField(
                                title: "Confirm Password",
                                icon: "lock.shield.fill",
                                text: $confirmPassword,
                                placeholder: "Re-enter password",
                                field: .confirmPassword,
                                isSecure: true,
                                keyboardType: .default,
                                contentType: .newPassword,
                                autocapitalization: .never
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: mode)
                    
                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(0.1))
                        )
                    }
                    
                    // Submit button
                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            } else {
                                Image(systemName: mode == .signUp ? "person.badge.plus" : "arrow.right.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(mode == .signUp ? "Create Account" : "Sign In")
                                    .font(.body.weight(.bold))
                            }
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                    }
                    .disabled(isLoading || !isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.5)
                    
                    // Forgot Password (sign-in mode only)
                    if mode == .signIn {
                        Button {
                            resetEmail = email
                            showResetPassword = true
                        } label: {
                            Text("Forgot Password?")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(BrandColors.goldBase)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle(mode == .signUp ? "Create Account" : "Sign In with Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
            .alert("Reset Password", isPresented: $showResetPassword) {
                TextField("Email address", text: $resetEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Send Reset Link") {
                    Task {
                        do {
                            try await authManager.resetPassword(email: resetEmail)
                            resetSent = true
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter your email address and we'll send you a link to reset your password.")
            }
            .alert("Check Your Email", isPresented: $resetSent) {
                Button("OK") { }
            } message: {
                Text("A password reset link has been sent to \(resetEmail). Check your inbox and follow the instructions.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Validation
    
    private var isFormValid: Bool {
        let emailValid = !email.isEmpty && email.contains("@") && email.contains(".")
        let passwordValid = password.count >= 6
        
        if mode == .signUp {
            let confirmValid = password == confirmPassword
            let nameValid = !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            return emailValid && passwordValid && confirmValid && nameValid
        }
        return emailValid && passwordValid
    }
    
    // MARK: - Submit
    
    private func submit() {
        guard isFormValid else { return }
        errorMessage = nil
        isLoading = true
        impactLight.impactOccurred()
        focusedField = nil
        
        Task {
            do {
                if mode == .signUp {
                    try await authManager.signUpWithEmail(
                        email: email.trimmingCharacters(in: .whitespaces),
                        password: password,
                        displayName: displayName.trimmingCharacters(in: .whitespaces)
                    )
                } else {
                    try await authManager.signInWithEmail(
                        email: email.trimmingCharacters(in: .whitespaces),
                        password: password
                    )
                }
                
                // Success -- dismiss
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = friendlyErrorMessage(from: error)
                }
            }
        }
    }
    
    /// Convert Firebase errors to user-friendly messages
    private func friendlyErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        
        switch nsError.code {
        case 17005: return "This account has been disabled. Please contact support."
        case 17008: return "Please enter a valid email address."
        case 17009: return "Incorrect password. Please try again."
        case 17011: return "No account found with this email. Try creating an account."
        case 17007: return "An account with this email already exists. Try signing in."
        case 17026: return "Password must be at least 6 characters."
        case 17010: return "Too many attempts. Please try again later."
        default: return error.localizedDescription
        }
    }
    
    // MARK: - Reusable Field
    
    private func authField(
        title: String,
        icon: String,
        text: Binding<String>,
        placeholder: String,
        field: Field,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        contentType: UITextContentType? = nil,
        autocapitalization: TextInputAutocapitalization = .never
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
                    .frame(width: 20)
                
                Group {
                    if isSecure {
                        SecureField(placeholder, text: text)
                    } else {
                        TextField(placeholder, text: text)
                    }
                }
                .font(.body)
                .foregroundColor(DS.Adaptive.textPrimary)
                .keyboardType(keyboardType)
                .textContentType(contentType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(autocapitalization)
                .focused($focusedField, equals: field)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                focusedField == field ? BrandColors.goldBase : DS.Adaptive.stroke,
                                lineWidth: focusedField == field ? 1.5 : 0.5
                            )
                    )
            )
        }
    }
}
