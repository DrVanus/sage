import SwiftUI

/// A shared, brand-styled "Source" menu matching the trading page timeframe picker style.
/// Uses native SwiftUI Menu with styling that matches the trading page dropdowns.
struct TechnicalsSourceMenu: View {
    let sourceLabel: String
    let preferred: TechnicalsViewModel.TechnicalsSourcePreference
    let requestedSource: TechnicalsViewModel.TechnicalsSourcePreference
    let isSwitchingSource: Bool
    let onSelect: (TechnicalsViewModel.TechnicalsSourcePreference) -> Void

    @State private var lastNonEmptyDisplay: String = ""
    @State private var showSourcePicker: Bool = false
    
    private let goldLight = BrandColors.goldLight
    
    private enum Motion {
        static let standard: Double = 0.18
        static let press: Double = 0.12
    }

    private func displaySourceLabel(_ source: String) -> String {
        let lower = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("no data") { return "" }
        if lower.isEmpty { return "" }
        
        var base: String = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let isStale = lower.contains("stale")
        let isFallback = lower.contains("fallback")
        
        // Map to display names - check CryptoSage first (most specific)
        if lower.contains("cryptosage") || lower.contains("firebase") {
            base = "CryptoSage"
        } else if lower.contains("coinbase") {
            base = "Coinbase"
        } else if lower.contains("binance") {
            base = "Binance"
        } else if lower.contains("sparkline") {
            base = "On-Device"
        } else if lower.contains("memory") || lower.contains("cache") || lower.contains("cached") {
            // Cached data from a previous exchange fetch - show as ready
            base = "Cached"
        } else if lower.contains("loading") {
            // Actually still loading
            base = "Loading..."
        } else if lower == "auto"
            || lower.contains("internal")
            || lower.contains("on-device")
            || lower.contains("on device")
            || lower.contains("derived")
            || lower.contains("local")
            || lower.contains("offline") {
            base = "On-Device"
        }
        
        // Clean professional labels - no fallback/stale indicators shown to users
        // The checkmark in the picker shows user preference; source label shows actual data source
        _ = isFallback  // Silence unused variable warning
        _ = isStale     // Silence unused variable warning
        
        return base
    }
    
    private let sources: [(TechnicalsViewModel.TechnicalsSourcePreference, String)] = [
        (.cryptosage, "CryptoSage"),  // Firebase-backed shared technicals (recommended)
        (.coinbase, "Coinbase"),
        (.binance, "Binance")
    ]

    var body: some View {
        let current = displaySourceLabel(sourceLabel)
        let effectiveDisplay = isSwitchingSource
            ? requestedSource.displayName
            : (current.isEmpty ? (lastNonEmptyDisplay.isEmpty ? requestedSource.displayName : lastNonEmptyDisplay) : current)

        // PROFESSIONAL UX: Trigger button shows active state when picker is open
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            showSourcePicker = true
        } label: {
            // Trading page style: clean capsule chip with chevron
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    // PROFESSIONAL UX: Brighter gold when active
                    .foregroundStyle(showSourcePicker ? goldLight : goldLight.opacity(0.85))
                
                Text("Source")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                if !effectiveDisplay.isEmpty {
                    Text("·")
                        .font(.caption)
                        .foregroundColor(showSourcePicker ? goldLight : DS.Adaptive.textTertiary)
                    
                    // Show loading spinner when actively fetching a newly requested source
                    if isSwitchingSource {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }
                    
                    Text(effectiveDisplay)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        // PROFESSIONAL UX: Gold text when active
                        .foregroundColor(showSourcePicker ? goldLight : DS.Adaptive.textSecondary)
                }
                
                // PROFESSIONAL UX: Chevron flips up when active
                Image(systemName: showSourcePicker ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(showSourcePicker ? goldLight : DS.Adaptive.textTertiary)
            }
            // PROFESSIONAL UX: Gold text when active
            .foregroundColor(showSourcePicker ? goldLight : DS.Adaptive.textPrimary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    // PROFESSIONAL UX: Gold tint background when active
                    .fill(showSourcePicker ? goldLight.opacity(0.12) : DS.Adaptive.cardBackground)
            )
            .overlay(
                Capsule()
                    // PROFESSIONAL UX: Gold border when active
                    .stroke(showSourcePicker ? goldLight : DS.Adaptive.stroke, lineWidth: showSourcePicker ? 1.0 : 0.8)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: Motion.standard), value: showSourcePicker)
        .animation(.easeInOut(duration: Motion.standard), value: isSwitchingSource)
        .popover(isPresented: $showSourcePicker, arrowEdge: .bottom) {
            TechnicalsSourcePickerPopover(
                isPresented: $showSourcePicker,
                sources: sources,
                preferred: preferred,
                onSelect: onSelect,
                transitionDuration: Motion.standard
            )
            .presentationCompactAdaptation(.popover)
        }
        .onAppear {
            DispatchQueue.main.async {
                if !current.isEmpty { lastNonEmptyDisplay = current }
            }
        }
        .onChange(of: current) { _, newVal in
            DispatchQueue.main.async {
                if !newVal.isEmpty { lastNonEmptyDisplay = newVal }
            }
        }
    }
}

// MARK: - Technicals Source Picker Popover
// PROFESSIONAL UX: Selection confirmation, press states, and smooth transitions
private struct TechnicalsSourcePickerPopover: View {
    @Binding var isPresented: Bool
    let sources: [(TechnicalsViewModel.TechnicalsSourcePreference, String)]
    /// The user's preferred source - checkmark shows this selection
    let preferred: TechnicalsViewModel.TechnicalsSourcePreference
    let onSelect: (TechnicalsViewModel.TechnicalsSourcePreference) -> Void
    let transitionDuration: Double
    @Environment(\.colorScheme) private var colorScheme
    
    // PROFESSIONAL UX: Track pending selection for immediate visual feedback
    @State private var pendingSelection: TechnicalsViewModel.TechnicalsSourcePreference? = nil
    @State private var isClosing: Bool = false
    
    // The visually selected item (pending selection takes precedence for immediate feedback)
    private var visuallySelected: TechnicalsViewModel.TechnicalsSourcePreference {
        pendingSelection ?? preferred
    }
    
    /// Source descriptions for better UX
    private func description(for source: TechnicalsViewModel.TechnicalsSourcePreference) -> String {
        switch source {
        case .cryptosage: return "30+ indicators, AI insights"
        case .coinbase: return "Exchange data"
        case .binance: return "Exchange data"
        }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Header
            HStack {
                Text("Data Source")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                Spacer(minLength: 6)
                Button(action: {
                    guard !isClosing else { return }
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            
            // Source options
            VStack(spacing: 4) {
                ForEach(sources, id: \.0) { source in
                    sourceRow(source: source)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 6)
        // PERFORMANCE FIX v19: Replaced .ultraThinMaterial
        .background(DS.Adaptive.chipBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .frame(minWidth: 220, maxWidth: 260)
    }
    
    @ViewBuilder
    private func sourceRow(source: (TechnicalsViewModel.TechnicalsSourcePreference, String)) -> some View {
        // PROFESSIONAL UX: Use visuallySelected to show immediate feedback on tap
        let isSelected = visuallySelected == source.0
        let isNewSelection = source.0 == pendingSelection && source.0 != preferred
        
        Button {
            guard !isClosing else { return }
            
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            
            // If tapping the already-selected item, just close immediately
            if source.0 == preferred {
                isPresented = false
                return
            }
            
            // PROFESSIONAL UX: Show selection confirmation before closing
            // 1. Immediately highlight the tapped item
            withAnimation(.easeInOut(duration: transitionDuration)) {
                pendingSelection = source.0
            }
            
            let selectedSource = source.0
            
            // 2. Brief delay to show the highlight, then close and trigger selection
            isClosing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
                #if DEBUG
                print("[TechnicalsSourceMenu] Source selected: \(selectedSource)")
                #endif
                onSelect(selectedSource)
                isPresented = false
            }
        } label: {
            HStack(spacing: 10) {
                // Checkmark for selected source
                ZStack {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DS.Colors.gold)
                    } else {
                        Circle()
                            .stroke(DS.Adaptive.textTertiary.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                    }
                }
                .frame(width: 20)
                
                // Source name and description
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(source.1)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isSelected ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
                        
                    }
                    
                    Text(description(for: source.0))
                        .font(.caption2)
                        .foregroundStyle(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    // PROFESSIONAL UX: Gold tint for selected, clear for others
                    .fill(isSelected ? DS.Colors.gold.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    // PROFESSIONAL UX: Gold border for selected
                    .stroke(isSelected ? DS.Colors.gold.opacity(0.4) : Color.clear, lineWidth: 0.5)
            )
            // PROFESSIONAL UX: Subtle scale for new selection confirmation
            .scaleEffect(isNewSelection ? 1.02 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(TechnicalsSourceRowButtonStyle())
        .accessibilityLabel(Text("\(source.1), \(description(for: source.0))"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// PROFESSIONAL UX: Button style with press state feedback
private struct TechnicalsSourceRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
