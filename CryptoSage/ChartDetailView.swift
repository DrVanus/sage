//
//  ChartDetailView.swift
//  CryptoSage
//
//  Created by DM on 5/27/25.
//

//
//  ChartDetailView.swift
//  CryptoSage
//
//  Created by ChatGPT on 05/27/25
//


import SwiftUI

#if DEBUG
import Combine

/// A dummy PriceService for SwiftUI previews
private struct PreviewPriceService: PriceService {
    func pricePublisher(for symbols: [String], interval: TimeInterval) -> AnyPublisher<[String: Double], Never> {
        Just([:]).eraseToAnyPublisher()
    }
}
#endif

/// A full-screen detailed chart view that embeds PortfolioChartView
/// with metrics, mode toggles, and swipe-down to dismiss.
struct ChartDetailView: View {
    @State private var chartMode: ChartViewType = .line
    @EnvironmentObject private var portfolioVM: PortfolioViewModel
    @Environment(\.presentationMode) private var presentationMode
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragLocation: CGPoint? = nil

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with dismiss
                HStack {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("Portfolio Chart")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    // Placeholder for balance
                    Color.clear.frame(width: 24)
                }
                .padding()

                // Detailed interactive chart
                GeometryReader { geo in
                    PortfolioChartView(
                        portfolioVM: portfolioVM,
                        showMetrics: true,
                        showSelector: true,
                        chartMode: $chartMode
                    )
                    .scaleEffect(scale, anchor: .center)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                scale *= delta
                                lastScale = value
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            }
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                dragLocation = gesture.location
                            }
                            .onEnded { _ in
                                dragLocation = nil
                            }
                    )
                    .overlay(
                        Group {
                            if let loc = dragLocation {
                                Path { path in
                                    path.move(to: CGPoint(x: loc.x, y: 0))
                                    path.addLine(to: CGPoint(x: loc.x, y: geo.size.height))
                                }
                                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 1, dash: [5]))
                            }
                        }
                    )
                }
                .frame(height: 300)
                .padding(.horizontal)
                .padding(.bottom, 16)

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}

struct ChartDetailView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a sample repository and view model for preview
        let repo = PortfolioRepository(
            manualService: ManualPortfolioDataService(),
            liveService: LivePortfolioDataService(),
            priceService: PreviewPriceService()
        )
        let vm = PortfolioViewModel(repository: repo)
        return ChartDetailView()
            .environmentObject(vm)
    }
}
