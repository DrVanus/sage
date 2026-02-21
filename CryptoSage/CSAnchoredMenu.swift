import SwiftUI
import UIKit

// MARK: - CSAnchoredMenuItem
/// A simple item model for CSAnchoredMenu.
public struct CSAnchoredMenuItem: Identifiable {
    public let id: String
    public let title: String
    public let iconSystemName: String?
    public let isEnabled: Bool
    public let isSelected: Bool
    public let action: () -> Void

    public init(id: String = UUID().uuidString,
                title: String,
                iconSystemName: String? = nil,
                isEnabled: Bool = true,
                isSelected: Bool = false,
                action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.action = action
    }
}

// MARK: - CSAnchoredMenu
/// A lightweight anchored popover menu that positions itself relative to an anchor rect (in global coordinates).
/// It renders a dimmed backdrop, a soft-styled panel, and a scrollable list of actions.
public struct CSAnchoredMenu: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding private var isPresented: Bool
    private let anchorRect: CGRect
    private let items: [CSAnchoredMenuItem]
    private let preferredWidth: CGFloat
    private let maxHeight: CGFloat
    private let edgePadding: CGFloat
    
    public init(isPresented: Binding<Bool>,
                anchorRect: CGRect,
                items: [CSAnchoredMenuItem],
                preferredWidth: CGFloat = 260,
                maxHeight: CGFloat = 320,
                edgePadding: CGFloat = 14) {
        self._isPresented = isPresented
        self.anchorRect = anchorRect
        self.items = items
        self.preferredWidth = preferredWidth
        self.maxHeight = maxHeight
        self.edgePadding = edgePadding
    }
    
    // Always use live anchor rect - no caching to prevent stale positions after rotation
    private var effectiveAnchorRect: CGRect {
        anchorRect
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Backdrop - stronger dim for better visibility
                Color.black.opacity(0.50)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { isPresented = false }

                // Menu panel positioned relative to anchor (with pointer nub)
                panelWithPointer(in: geo)
                    .transition(.scale.combined(with: .opacity))
            }
            .transaction { tx in tx.animation = nil } // avoid implicit animations inside
        }
    }

    // MARK: - Panel
    private var panel: some View {
        let isDark = colorScheme == .dark
        let panelBase = isDark ? Color(red: 0.10, green: 0.10, blue: 0.12) : Color(uiColor: .systemBackground)
        let panelTop = isDark ? Color(red: 0.14, green: 0.14, blue: 0.16) : Color(uiColor: .secondarySystemBackground)
        let separator = isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
        let borderTop = isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.12)
        let borderBottom = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        
        // Estimated row height for positioning math; actual layout uses flexible rows
        let _ = ()
        return VStack(spacing: 0) {
            ScrollView(showsIndicators: true) {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        buttonRow(item)
                        if item.id != items.last?.id {
                            Rectangle()
                                .fill(separator)
                                .frame(height: 0.8)
                                .padding(.leading, 28)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
            }
        }
        .background(
            ZStack {
                // Solid panel background for consistent contrast.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(panelBase)
                
                // Subtle inner gradient for depth
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [panelTop, panelBase],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Top highlight for premium feel
                LinearGradient(colors: [Color.white.opacity(isDark ? 0.08 : 0.18), .clear], startPoint: .top, endPoint: .center)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                // Border
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [borderTop, borderBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        )
        .compositingGroup()
        .accessibilityElement(children: .contain)
    }

    // MARK: - Button Row
    private func buttonRow(_ item: CSAnchoredMenuItem) -> some View {
        let isDark = colorScheme == .dark
        let baseText = isDark ? Color.white : Color.black.opacity(0.88)
        let selectedBg = isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        let selectedStroke = isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.16)
        
        return Button {
            guard item.isEnabled else { return }
            item.action()
            isPresented = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .opacity(item.isSelected ? 1 : 0)
                    .foregroundColor(Color.yellow)
                    .frame(width: 16)
                if let icon = item.iconSystemName {
                    Image(systemName: icon)
                        .foregroundColor(baseText)
                        .opacity(item.isEnabled ? 0.95 : 0.45)
                }
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(item.isEnabled ? baseText : baseText.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.isSelected ? selectedBg : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(item.isSelected ? selectedStroke : .clear, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    }

    // MARK: - Positioning
    private func menuPosition(in geo: GeometryProxy) -> CGPoint {
        // Position relative to the container (the view that applied .overlay),
        // so the panel always remains usable/visible even when the card is short
        // or when the screen has more space outside the card.
        let containerGlobal = geo.frame(in: .global)

        // If the anchor is unknown, fall back to the top center of the container
        let anchor: CGRect = (effectiveAnchorRect == .zero)
            ? CGRect(x: containerGlobal.midX - 44,
                     y: containerGlobal.minY + 52,
                     width: 88,
                     height: 36)
            : effectiveAnchorRect

        // Estimated height used to decide above/below and clamping
        let estimatedHeight = min(maxHeight, CGFloat(items.count) * 44 + 12)

        // Available space WITHIN the container
        let availableBelow = max(0, containerGlobal.maxY - anchor.maxY)
        let availableAbove = max(0, anchor.minY - containerGlobal.minY)

        // Prefer below if it fits inside the container; otherwise prefer above
        let placeBelow = (availableBelow >= estimatedHeight) || (availableBelow >= availableAbove)

        // Compute target center in GLOBAL coordinates, clamped to container
        let globalY: CGFloat = {
            if placeBelow {
                let raw = anchor.maxY + 8
                let maxY = containerGlobal.maxY - edgePadding
                return min(maxY, raw + estimatedHeight / 2)
            } else {
                let rawTop = anchor.minY - 8 - estimatedHeight
                let minY = containerGlobal.minY + edgePadding
                return max(minY + estimatedHeight / 2, rawTop + estimatedHeight / 2)
            }
        }()

        // Horizontal: prefer centering over the anchor; if clamped, try leading/trailing alignment
        let minX = containerGlobal.minX + edgePadding
        let maxX = containerGlobal.maxX - edgePadding
        let halfW = preferredWidth / 2
        let minCenter = minX + halfW
        let maxCenter = maxX - halfW

        // Ideal centers for different alignments
        let centerIdeal   = anchor.midX
        let leadingIdeal  = anchor.minX + halfW
        let trailingIdeal = anchor.maxX - halfW

        // Clamp helper
        func clampCenter(_ x: CGFloat) -> CGFloat { max(minCenter, min(maxCenter, x)) }

        // Start with centered; if it requires heavy clamping, pick the better of leading/trailing
        var globalX = clampCenter(centerIdeal)
        let centerClampDelta = abs(centerIdeal - globalX)
        if centerClampDelta > 12 { // significant clamp → try edge-aligned variants
            let lead = clampCenter(leadingIdeal)
            let trail = clampCenter(trailingIdeal)
            let leadDelta = abs(leadingIdeal - lead)
            let trailDelta = abs(trailingIdeal - trail)
            globalX = (leadDelta <= trailDelta) ? lead : trail
        }

        // Convert to the GeometryReader's local space
        let localX = globalX - containerGlobal.minX
        let localY = globalY - containerGlobal.minY
        return CGPoint(x: localX, y: localY)
    }

    // Compose the menu panel and add a small pointer nub aligned to the anchor
    private func panelWithPointer(in geo: GeometryProxy) -> some View {
        let w = effectiveWidth(in: geo)
        let center = menuPosition(in: geo)
        let containerGlobal = geo.frame(in: .global)
        let anchor: CGRect = (effectiveAnchorRect == .zero)
            ? CGRect(x: containerGlobal.midX - 44,
                     y: containerGlobal.minY + 52,
                     width: 88,
                     height: 36)
            : effectiveAnchorRect

        // Recompute placement so the nub knows whether to attach to the top or bottom
        let estimatedHeight = min(maxHeight, CGFloat(items.count) * 44 + 12)
        let availableBelow = max(0, containerGlobal.maxY - anchor.maxY)
        let availableAbove = max(0, anchor.minY - containerGlobal.minY)
        let placeBelow = (availableBelow >= estimatedHeight) || (availableBelow >= availableAbove)

        // Compute nub x within the panel's local coordinates, clamped with padding
        let leftX = center.x - w / 2
        let clampPad: CGFloat = 14
        let nubXLocal = max(clampPad, min(w - clampPad, anchor.midX - leftX))
        let nubSize: CGFloat = 12

        return panel
            .frame(width: w)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: maxHeight)
            .overlay(alignment: placeBelow ? .topLeading : .bottomLeading) {
                PointerDiamond()
                    .frame(width: nubSize, height: nubSize)
                    .offset(x: nubXLocal - nubSize / 2,
                            y: placeBelow ? -nubSize / 2 + 1 : nubSize / 2 - 1)
                    .allowsHitTesting(false)
            }
            .position(center)
    }

    // Small diamond-shaped pointer to visually anchor the menu to the source pill
    private struct PointerDiamond: View {
        var body: some View {
            ZStack {
                // SOLID dark background matching the panel
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                
                // Border matching panel
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
            }
            .rotationEffect(.degrees(45))
        }
    }

    // Compute a compact width using real text measurement so there's no wasted trailing space
    private func effectiveWidth(in geo: GeometryProxy) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        // Measure the widest title with UIKit so we don't over-estimate
        let longestTextWidth: CGFloat = items.map { item in
            let size = (item.title as NSString).size(withAttributes: [.font: font])
            return ceil(size.width)
        }.max() ?? 80

        // Row composition constants (keep in sync with buttonRow)
        let rowHPad: CGFloat = 8               // horizontal padding inside each row (tightened)
        let checkWidth: CGFloat = 16           // checkmark frame width (tightened)
        let spacingAfterCheck: CGFloat = 6     // spacing between checkmark and text/icon (tightened)
        let iconSpace: CGFloat = items.contains(where: { $0.iconSystemName != nil }) ? (16 + 6) : 0
        let scrollHPad: CGFloat = 4            // horizontal padding on the inner VStack (tightened)

        // Total content width needed for the longest row
        let contentWidth = rowHPad + checkWidth + spacingAfterCheck + iconSpace + longestTextWidth + rowHPad
        let estimated = contentWidth + scrollHPad * 2

        // Clamp to container and preferred bounds
        let containerMax = max(200, geo.size.width - edgePadding * 2)
        let minW: CGFloat = 176
        let maxW: CGFloat = min(preferredWidth, containerMax)
        return max(minW, min(estimated, maxW))
    }
}

// MARK: - Reusable Anchored Selection Control
public struct CSAnchoredSelectionOption: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let iconSystemName: String?
    public let isEnabled: Bool
    
    public init(id: String, title: String, iconSystemName: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
        self.isEnabled = isEnabled
    }
}

private struct CSAnchoredSelectionFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Reusable dropdown trigger + anchored menu control.
/// Use a shared `activeFieldID` binding across sibling controls to guarantee only one dropdown is open.
public struct CSAnchoredSelectionField: View {
    public let fieldID: String
    public let defaultTitle: String
    public let defaultIconSystemName: String?
    public let preferredMenuWidth: CGFloat
    public let menuMaxHeight: CGFloat
    public let options: [CSAnchoredSelectionOption]
    public let accentColor: Color
    
    @Binding public var selectedID: String?
    @Binding public var activeFieldID: String?
    
    @State private var buttonFrame: CGRect = .zero
    
    public init(
        fieldID: String,
        defaultTitle: String,
        defaultIconSystemName: String? = nil,
        preferredMenuWidth: CGFloat = 220,
        menuMaxHeight: CGFloat = 360,
        options: [CSAnchoredSelectionOption],
        accentColor: Color = .blue,
        selectedID: Binding<String?>,
        activeFieldID: Binding<String?>
    ) {
        self.fieldID = fieldID
        self.defaultTitle = defaultTitle
        self.defaultIconSystemName = defaultIconSystemName
        self.preferredMenuWidth = preferredMenuWidth
        self.menuMaxHeight = menuMaxHeight
        self.options = options
        self.accentColor = accentColor
        self._selectedID = selectedID
        self._activeFieldID = activeFieldID
    }
    
    private var isPresented: Bool {
        activeFieldID == fieldID
    }
    
    private var selectedOption: CSAnchoredSelectionOption? {
        guard let selectedID else { return nil }
        return options.first(where: { $0.id == selectedID })
    }
    
    private var menuItems: [CSAnchoredMenuItem] {
        options.map { option in
            CSAnchoredMenuItem(
                id: option.id,
                title: option.title,
                iconSystemName: option.iconSystemName,
                isEnabled: option.isEnabled,
                isSelected: selectedID == option.id
            ) {
                selectedID = option.id
            }
        }
    }
    
    public var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.18)) {
                activeFieldID = isPresented ? nil : fieldID
            }
        } label: {
            HStack(spacing: 5) {
                if let icon = selectedOption?.iconSystemName ?? defaultIconSystemName {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isPresented ? accentColor : DS.Adaptive.textTertiary)
                }
                Text(selectedOption?.title ?? defaultTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isPresented ? 180 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isPresented)
            }
            .foregroundStyle(isPresented ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
            .frame(minWidth: 96)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isPresented ? accentColor.opacity(0.15) : DS.Adaptive.chipBackground)
            )
            .overlay(
                Capsule()
                    .stroke(isPresented ? accentColor.opacity(0.32) : DS.Adaptive.stroke.opacity(0.7), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CSAnchoredSelectionFrameKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        )
        .onPreferenceChange(CSAnchoredSelectionFrameKey.self) { frame in
            buttonFrame = frame
            if isPresented && frame == .zero {
                activeFieldID = nil
            }
        }
        .overlay {
            if isPresented {
                CSAnchoredMenu(
                    isPresented: Binding(
                        get: { activeFieldID == fieldID },
                        set: { activeFieldID = $0 ? fieldID : nil }
                    ),
                    anchorRect: buttonFrame,
                    items: menuItems,
                    preferredWidth: preferredMenuWidth,
                    maxHeight: menuMaxHeight,
                    edgePadding: 14
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
}

// MARK: - CSAnchoredGridMenu
/// A grid-based anchored menu for compact selection items like timeframes.
/// Similar to CSAnchoredMenu but renders items in a grid layout with gold selection highlight.
/// Features professional UX: press states, selection confirmation animation, and smooth transitions.
/// LIGHT/DARK MODE: Properly adapts colors for both light and dark modes.
public struct CSAnchoredGridMenu<Item: Hashable>: View {
    @Binding private var isPresented: Bool
    private let anchorRect: CGRect
    private let items: [Item]
    private let selectedItem: Item
    private let titleForItem: (Item) -> String
    private let onSelect: (Item) -> Void
    private let columns: Int
    private let preferredWidth: CGFloat
    private let edgePadding: CGFloat
    private let title: String?
    
    // PROFESSIONAL UX: Track the newly selected item to show confirmation before closing
    @State private var pendingSelection: Item? = nil
    @State private var isClosing: Bool = false
    
    // LIGHT/DARK MODE: Environment for adaptive colors
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    public init(
        isPresented: Binding<Bool>,
        anchorRect: CGRect,
        items: [Item],
        selectedItem: Item,
        titleForItem: @escaping (Item) -> String,
        onSelect: @escaping (Item) -> Void,
        columns: Int = 3,
        preferredWidth: CGFloat = 260,
        edgePadding: CGFloat = 12,
        title: String? = nil
    ) {
        self._isPresented = isPresented
        self.anchorRect = anchorRect
        self.items = items
        self.selectedItem = selectedItem
        self.titleForItem = titleForItem
        self.onSelect = onSelect
        self.columns = columns
        self.preferredWidth = preferredWidth
        self.edgePadding = edgePadding
        self.title = title
    }
    
    // Always use the live anchor rect - no caching to prevent stale positions
    private var effectiveAnchorRect: CGRect {
        anchorRect
    }
    
    // The visually selected item (pending selection takes precedence for immediate feedback)
    private var visuallySelectedItem: Item {
        pendingSelection ?? selectedItem
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Backdrop - adaptive dim for light/dark mode
                Color.black.opacity(isDark ? 0.50 : 0.30)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isClosing else { return }
                        isPresented = false
                    }
                
                // Menu panel positioned relative to anchor (with pointer nub)
                panelWithPointer(in: geo)
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Grid Panel
    // LIGHT/DARK MODE: Adaptive colors for both modes
    private var gridPanel: some View {
        VStack(spacing: 6) {
            // Optional header
            if let title = title {
                HStack {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isDark ? .white.opacity(0.85) : .black.opacity(0.75))
                    Spacer()
                    Button(action: {
                        guard !isClosing else { return }
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(isDark ? .white.opacity(0.6) : .black.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                
                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    .frame(height: 0.8)
            }
            
            // Grid of items
            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 5), count: columns)
            LazyVGrid(columns: gridColumns, spacing: 5) {
                ForEach(items, id: \.self) { item in
                    gridChip(for: item)
                }
            }
        }
        .padding(8)
        .background(
            ZStack {
                // LIGHT/DARK MODE: Adaptive background
                if isDark {
                    // Dark mode: solid dark background
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                    
                    // Subtle inner gradient for depth
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.14, green: 0.14, blue: 0.16), Color(red: 0.08, green: 0.08, blue: 0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Top highlight for premium feel
                    LinearGradient(colors: [Color.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    // Border
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.20), Color.white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                } else {
                    // Light mode: clean white/cream background
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                    
                    // Subtle gradient for depth
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color(uiColor: .systemGray6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
            }
        )
    }
    
    @ViewBuilder
    private func gridChip(for item: Item) -> some View {
        // PROFESSIONAL UX: Show gold highlight for both current selection AND pending selection
        let isSelected = item == visuallySelectedItem
        let isNewSelection = item == pendingSelection && item != selectedItem
        
        // LIGHT/DARK MODE: Adaptive text colors
        let unselectedTextColor: Color = isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.85)
        let unselectedBgColor: Color = isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
        let unselectedBorderColor: Color = isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
        
        Button {
            guard !isClosing else { return }  // Prevent double-tap during close animation
            
            #if os(iOS)
            // Stronger haptic for selection confirmation
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            
            // If tapping the already-selected item, just close immediately
            if item == selectedItem {
                isPresented = false
                return
            }
            
            // PERFORMANCE: Trigger selection immediately, then close menu fast.
            // The chart data loading starts the moment onSelect fires, so minimizing
            // the menu close delay reduces perceived latency.
            pendingSelection = item
            onSelect(item)
            
            isClosing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeOut(duration: 0.12)) {
                    isPresented = false
                }
            }
        } label: {
            Text(titleForItem(item))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                // LIGHT/DARK MODE: Adaptive text color - always black on gold, adaptive for unselected
                .foregroundStyle(isSelected ? Color.black : unselectedTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(chipGoldGradient) : AnyShapeStyle(unselectedBgColor))
                        if isSelected {
                            // Top gloss
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(LinearGradient(colors: [Color.white.opacity(0.20), .clear], startPoint: .top, endPoint: .center))
                        }
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isSelected ? AnyShapeStyle(ctaRimStrokeGradient) : AnyShapeStyle(unselectedBorderColor), lineWidth: 0.8)
                    }
                )
                // PROFESSIONAL UX: Subtle scale animation for new selection confirmation
                .scaleEffect(isNewSelection ? 1.05 : 1.0)
        }
        .buttonStyle(GridChipButtonStyle())
        .accessibilityLabel(Text(titleForItem(item)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    // MARK: - Positioning
    private func menuPosition(in geo: GeometryProxy) -> CGPoint {
        let containerGlobal = geo.frame(in: .global)
        let screenBounds = containerGlobal
        let anchor = effectiveAnchorRect
        
        // Estimated height based on rows
        let rowCount = ceil(Double(items.count) / Double(columns))
        let estimatedHeight: CGFloat = (title != nil ? 30 : 0) + CGFloat(rowCount) * 38 + 16
        
        // Compute available space using screen bounds for better positioning
        let spaceBelow = screenBounds.maxY - anchor.maxY - 20 // safe area margin
        let spaceAbove = anchor.minY - screenBounds.minY - 60 // nav bar margin
        
        let placeBelow = spaceBelow >= estimatedHeight || spaceBelow >= spaceAbove
        
        // Vertical position - use screen-relative positioning for stability
        let globalY: CGFloat
        if placeBelow {
            globalY = anchor.maxY + 8 + estimatedHeight / 2
        } else {
            globalY = anchor.minY - 8 - estimatedHeight / 2
        }
        
        // Horizontal: center on anchor, clamped to screen edges
        let halfW = preferredWidth / 2
        var globalX = anchor.midX
        globalX = max(edgePadding + halfW, min(screenBounds.width - edgePadding - halfW, globalX))
        
        // Convert to local coordinates
        let localX = globalX - containerGlobal.minX
        let localY = globalY - containerGlobal.minY
        
        return CGPoint(x: localX, y: localY)
    }
    
    private func panelWithPointer(in geo: GeometryProxy) -> some View {
        let center = menuPosition(in: geo)
        let containerGlobal = geo.frame(in: .global)
        let anchor = effectiveAnchorRect
        
        // Determine if placing below or above
        let rowCount = ceil(Double(items.count) / Double(columns))
        let estimatedHeight: CGFloat = (title != nil ? 30 : 0) + CGFloat(rowCount) * 38 + 16
        let screenBounds = containerGlobal
        let spaceBelow = screenBounds.maxY - anchor.maxY - 20
        let spaceAbove = anchor.minY - screenBounds.minY - 60
        let placeBelow = spaceBelow >= estimatedHeight || spaceBelow >= spaceAbove
        
        // Compute nub x position using captured anchor
        let leftX = center.x - preferredWidth / 2
        let clampPad: CGFloat = 16
        let nubXLocal = max(clampPad, min(preferredWidth - clampPad, (anchor.midX - containerGlobal.minX) - leftX))
        let nubSize: CGFloat = 10
        
        return gridPanel
            .frame(width: preferredWidth)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: placeBelow ? .topLeading : .bottomLeading) {
                AnchoredPointerNub()
                    .frame(width: nubSize, height: nubSize)
                    .offset(x: nubXLocal - nubSize / 2,
                            y: placeBelow ? -nubSize / 2 + 1 : nubSize / 2 - 1)
                    .allowsHitTesting(false)
            }
            .position(center)
    }
}

// MARK: - Grid Chip Button Style
/// Custom button style for grid chips with press state feedback
private struct GridChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // PROFESSIONAL UX: Scale down slightly when pressed for tactile feedback
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            // Subtle brightness change on press
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Shared Pointer Nub
// LIGHT/DARK MODE: Adaptive colors for the pointer nub
private struct AnchoredPointerNub: View {
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        ZStack {
            // LIGHT/DARK MODE: Adaptive background matching the panel
            if isDark {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(uiColor: .systemGray6))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
            }
        }
        .rotationEffect(.degrees(45))
    }
}

// MARK: - Preview (optional in debug builds)
#if DEBUG
struct CSAnchoredMenu_Previews: PreviewProvider {
    static var previews: some View {
        StatefulPreviewWrapper(true) { isPresented in
            ZStack {
                Color.black.ignoresSafeArea()
                let anchor = CGRect(x: 180, y: 220, width: 120, height: 36)
                CSAnchoredMenu(
                    isPresented: isPresented,
                    anchorRect: anchor,
                    items: [
                        .init(title: "Option A", isSelected: true) {},
                        .init(title: "Option B") {},
                        .init(title: "Disabled", isEnabled: false) {}
                    ]
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Utility wrapper to preview a Binding
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content
    init(_ value: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: value)
        self.content = content
    }
    var body: some View { content($value) }
}
#endif
