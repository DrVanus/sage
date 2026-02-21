//
//  ChatTextField.swift
//  CryptoSage
//
//  UIViewRepresentable wrapper for UITextField to ensure reliable keyboard focus.
//  SwiftUI's @FocusState can be unreliable in complex view hierarchies.
//

import SwiftUI
import UIKit

/// A UIKit-backed text field that reliably shows the keyboard when tapped.
/// Use this instead of SwiftUI's TextField when keyboard focus is unreliable.
struct ChatTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Type a message..."
    var returnKeyType: UIReturnKeyType = .send
    var onCommit: (() -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        
        // Basic configuration
        textField.placeholder = placeholder
        textField.returnKeyType = returnKeyType
        textField.autocorrectionType = .default
        textField.autocapitalizationType = .sentences
        textField.spellCheckingType = .default
        textField.borderStyle = .none
        textField.contentVerticalAlignment = .center
        
        // Styling - adaptive for light/dark mode
        textField.textColor = .label
        textField.tintColor = .label
        textField.font = .systemFont(ofSize: 15)
        textField.backgroundColor = .clear
        
        // Styled placeholder - adaptive for light/dark mode
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.secondaryLabel]
        )
        
        // Enable clear button
        textField.clearButtonMode = .whileEditing
        
        // Set content hugging to allow flexible width
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // Add target for text changes
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textFieldDidChange(_:)),
            for: .editingChanged
        )
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        // Only update if text differs to avoid cursor jumping
        if uiView.text != text {
            uiView.text = text
        }
        
        // Update placeholder if changed
        if uiView.placeholder != placeholder {
            uiView.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ChatTextField
        
        init(_ parent: ChatTextField) {
            self.parent = parent
        }
        
        @objc func textFieldDidChange(_ textField: UITextField) {
            // Update the binding
            parent.text = textField.text ?? ""
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onEditingChanged?(true)
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onEditingChanged?(false)
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            // Call the onCommit closure when return/send is pressed
            parent.onCommit?()
            return true
        }
    }
}

// MARK: - Convenience Modifiers

extension ChatTextField {
    /// Set a custom placeholder text
    func placeholder(_ text: String) -> ChatTextField {
        var copy = self
        copy.placeholder = text
        return copy
    }
    
    /// Set the return key type
    func returnKey(_ type: UIReturnKeyType) -> ChatTextField {
        var copy = self
        copy.returnKeyType = type
        return copy
    }
    
    /// Called when the return key is pressed
    func onSubmit(_ action: @escaping () -> Void) -> ChatTextField {
        var copy = self
        copy.onCommit = action
        return copy
    }
    
    /// Called when editing state changes (focused/unfocused)
    func onEditingChanged(_ action: @escaping (Bool) -> Void) -> ChatTextField {
        var copy = self
        copy.onEditingChanged = action
        return copy
    }
}

// MARK: - Helper to dismiss keyboard

extension UIApplication {
    /// Dismiss the keyboard from anywhere in the app
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Preview

struct ChatTextField_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                Spacer()
                
                HStack(spacing: 12) {
                    ChatTextField(text: .constant(""), placeholder: "Ask me anything...")
                        .frame(height: 44)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.1))
                        )
                    
                    Button("Send") {}
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.yellow)
                        .cornerRadius(10)
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
    }
}
