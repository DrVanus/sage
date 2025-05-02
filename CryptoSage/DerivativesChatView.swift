//
//  DerivativesChatView.swift
//  CryptoSage
//
//  Created by DM on 5/29/25.
//

import SwiftUI
import UIKit

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    return f
}()

// Custom shape to round specific corners
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct DerivativesChatView: View {
    @ObservedObject var viewModel: DerivativesBotViewModel
    @Environment(\.presentationMode) private var presentationMode
    @State private var messageText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(viewModel.chatMessages) { msg in
                        ChatMessageRow(message: msg)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                TextField("Enter your strategy...", text: $messageText)
                    .padding(.leading, 16)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .foregroundColor(.white)

                Button {
                    viewModel.sendChatMessage(messageText)
                    messageText = ""
                } label: {
                    Text("Send")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)
        }
        .background(Color.black)
    }
}


struct DerivativesChatView_Previews: PreviewProvider {
    static var previews: some View {
        DerivativesChatView(viewModel: DerivativesBotViewModel())
    }
}

// MARK: - Chat Message Row
struct ChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.text)
                .font(.body)
                .foregroundColor(.white)
            Text(timeFormatter.string(from: message.timestamp))
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }
}
