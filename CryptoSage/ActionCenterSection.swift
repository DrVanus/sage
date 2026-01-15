import SwiftUI

struct ActionCenterSection: View {
    let result: RiskScanResult?
    let isScanning: Bool
    let lastScan: Date?
    let overlayActive: Bool
    let onScan: () -> Void
    let onViewReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(systemImage: "shield.checkerboard", title: "Action Center")
                .padding(.horizontal, 16)

            HStack(alignment: .top, spacing: 12) {
                CardContainer {
                    RiskScanCard(
                        result: result,
                        isScanning: isScanning,
                        lastScan: lastScan,
                        overlayActive: overlayActive,
                        onScan: onScan,
                        onViewReport: onViewReport
                    )
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 96)

                CardContainer {
                    InviteCard()
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 96)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 6)
    }
}
