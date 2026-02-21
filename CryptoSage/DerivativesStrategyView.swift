//
//  DerivativesStrategyView.swift
//  CryptoSage
//
//  Created by DM on 5/29/25.
//


//  DerivativesStrategyView.swift
//  CryptoSage
//
//  Created by DM on 5/29/25.
//

import SwiftUI

// MARK: - Main Strategy View
struct DerivativesStrategyView: View {
    @ObservedObject var viewModel: DerivativesBotViewModel
    
    var body: some View {
        DerivativesStrategyBasicView(viewModel: viewModel)
    }
}

// MARK: - Basic Strategy View
struct DerivativesStrategyBasicView: View {
    @ObservedObject var viewModel: DerivativesBotViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Grid Settings Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("GRID SETTINGS")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.horizontal)

                    VStack(spacing: 1) {
                        TextField("Lower Price", text: $viewModel.lowerPrice)
                            .keyboardType(.decimalPad)
                        TextField("Upper Price", text: $viewModel.upperPrice)
                            .keyboardType(.decimalPad)
                        TextField("Grid Levels", text: $viewModel.gridLevels)
                            .keyboardType(.numberPad)
                        TextField("Order Volume", text: $viewModel.orderVolume)
                            .keyboardType(.decimalPad)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            // LIGHT MODE FIX: Adaptive background
                            .fill(colorScheme == .dark ? Color.black.opacity(0.2) : Color.black.opacity(0.04))
                    )
                }

                // Generate Bot Config Button
                Button(action: { viewModel.generateDerivativesConfig() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Generate Bot Config")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    // LIGHT MODE FIX: Adaptive text on gold button
                    .foregroundColor(colorScheme == .dark ? .black : .white.opacity(0.95))
                    .background(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [BrandColors.goldLight, BrandColors.goldBase]
                                : [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.48, blue: 0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(14)
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
}

struct DerivativesStrategyBasicView_Previews: PreviewProvider {
    static var previews: some View {
        DerivativesStrategyBasicView(viewModel: DerivativesBotViewModel())
    }
}
