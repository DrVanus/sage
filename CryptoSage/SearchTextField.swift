//
//  SearchTextField.swift
//  CryptoSage
//
//  UIViewRepresentable wrapper for UITextField specifically designed for search.
//  Ensures reliable keyboard focus and proper search configuration.
//

import SwiftUI
import UIKit

/// A UIKit-backed text field optimized for search functionality.
/// - Disables autocapitalization and autocorrection
/// - Uses search return key
/// - Provides direct callbacks for text changes and submit
/// - Supports autoFocus to automatically show keyboard when appearing
struct SearchTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Search..."
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?
    var onSubmit: (() -> Void)?
    var onEditingChanged: ((Bool) -> Void)?  // Reports focus state changes
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        
        // Search-specific configuration
        textField.placeholder = placeholder
        textField.returnKeyType = .search
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        
        // Styling - adaptive for light/dark mode
        textField.textColor = .label
        textField.tintColor = .label
        textField.font = .systemFont(ofSize: 15)
        textField.backgroundColor = .clear
        
        // Styled placeholder
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.secondaryLabel]
        )
        
        // SEARCH FIX: Disable the built-in clear button to avoid duplicate X icons
        // (MarketView has its own clear button)
        textField.clearButtonMode = .never
        
        // Set content hugging to allow flexible width
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // Add target for text changes
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textFieldDidChange(_:)),
            for: .editingChanged
        )
        
        // Auto-focus: become first responder after a brief delay to ensure view is ready
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                textField.becomeFirstResponder()
            }
        }
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        // Only update if text differs to avoid cursor jumping
        if uiView.text != text {
            uiView.text = text
        }
        
        // Handle autoFocus state changes (e.g., when search bar becomes visible)
        // Note: We track in coordinator to avoid repeated focus attempts
        if autoFocus && !context.coordinator.hasAutoFocused && !uiView.isFirstResponder {
            context.coordinator.hasAutoFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                uiView.becomeFirstResponder()
            }
        } else if !autoFocus {
            // Reset flag when autoFocus is turned off
            context.coordinator.hasAutoFocused = false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SearchTextField
        var hasAutoFocused: Bool = false
        
        init(_ parent: SearchTextField) {
            self.parent = parent
        }
        
        @objc func textFieldDidChange(_ textField: UITextField) {
            let newText = textField.text ?? ""
            // Update the binding
            parent.text = newText
            // Call the text change callback directly
            parent.onTextChange?(newText)
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            // Call submit callback and dismiss keyboard
            parent.onSubmit?()
            textField.resignFirstResponder()
            return true
        }
        
        func textFieldShouldClear(_ textField: UITextField) -> Bool {
            // When clear button is tapped, update binding and call callback
            parent.text = ""
            parent.onTextChange?("")
            return true
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onEditingChanged?(true)
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onEditingChanged?(false)
        }
    }
}

// MARK: - Preview

struct SearchTextField_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                SearchTextField(
                    text: .constant(""),
                    placeholder: "Search coins...",
                    autoFocus: true, // Demo auto-focus
                    onTextChange: { text in
                        #if DEBUG
                        print("Text changed: \(text)")
                        #endif
                    },
                    onSubmit: {
                        #if DEBUG
                        print("Search submitted")
                        #endif
                    }
                )
                .frame(height: 44)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.1))
                )
                .padding()
            }
        }
        .preferredColorScheme(.dark)
    }
}
