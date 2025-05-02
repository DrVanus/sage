//
//  AIInsightView.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//

import SwiftUI

struct AIInsightView: View {
    @StateObject private var vm = AIInsightViewModel()
    @StateObject private var portfolioVM = PortfolioViewModel(repository: PortfolioRepository())

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.headline)
                    .foregroundColor(.yellow)
                Text("AI Insight")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    Task { await vm.refresh(using: portfolioVM.portfolio) }
                } label: {
                    if vm.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(width: 24, height: 24)
                            .padding(4)
                            .background(
                                Circle().fill(Color(uiColor: .systemBackground))
                            )
                    } else {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                            .padding(4)
                            .background(
                                Circle().fill(Color(uiColor: .systemBackground))
                            )
                    }
                }
                .disabled(vm.isLoading)
                .help("Generate a new AI insight")
            }

            Divider()

            if let text = vm.insight?.text {
                Text(text)
                    .font(.body)
            } else {
                Text("Press the refresh button to generate your first AI insight.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let timestamp = vm.insight?.timestamp {
                Text("Updated \(timestamp, style: .time)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .systemBackground))
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onAppear {
            if vm.insight == nil {
                Task { await vm.refresh(using: portfolioVM.portfolio) }
            }
        }
    }
}
