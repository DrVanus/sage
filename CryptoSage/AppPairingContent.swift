//
//  AppPairingContent.swift
//  CSAI1
//
//  Created by DM on 4/2/25.
//


import SwiftUI

struct AppPairingContent: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showComingSoonAlert = false

    var body: some View {
        ZStack {
            // A simple gradient background to set a modern tone.
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Pair Your App")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .padding(.top, 40)
                
                Text("Follow the steps below to pair your app with your account. Make sure your device is connected and your credentials are correct.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .padding(.horizontal)
                
                Spacer()
                
                Button(action: {
                    showComingSoonAlert = true
                }) {
                    Text("Pair Now")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green, Color.blue]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                
                Button(action: {
                    dismiss()
                }) {
                    Text("Cancel")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color.gray.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                
                Spacer()
            }
        }
        .alert("Coming Soon", isPresented: $showComingSoonAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Hardware wallet pairing is coming soon.")
        }
    }
}

struct AppPairingContent_Previews: PreviewProvider {
    static var previews: some View {
        AppPairingContent()
    }
}