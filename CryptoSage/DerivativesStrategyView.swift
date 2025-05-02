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

struct DerivativesStrategyView: View {
    @ObservedObject var viewModel: DerivativesBotViewModel

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
                            .fill(Color.black.opacity(0.2))
                    )
                }

                // Generate Bot Config Button
                Button(action: { viewModel.generateDerivativesConfig() }) {
                    Text("Generate Bot Config")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
}

struct DerivativesStrategyView_Previews: PreviewProvider {
    static var previews: some View {
        DerivativesStrategyView(viewModel: DerivativesBotViewModel())
    }
}