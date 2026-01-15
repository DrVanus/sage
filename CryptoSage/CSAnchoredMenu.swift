import SwiftUI

/// A single menu item for `CSAnchoredMenu`.
public struct CSAnchoredMenuItem: Identifiable {
    /// Unique identifier of the menu item.
    public let id: String
    /// The displayed title of the menu item.
    public let title: String
    /// The optional SF Symbol system name to display as an icon.
    public let iconSystemName: String?
    /// Whether the menu item is enabled and tappable.
    public let isEnabled: Bool
    /// Whether the menu item is currently selected.
    public let isSelected: Bool
    /// The action to perform when the menu item is tapped.
    public let action: () -> Void

    /// Creates a new anchored menu item.
    ///
    /// - Parameters:
    ///   - id: A unique string identifier.
    ///   - title: The menu item's title.
    ///   - iconSystemName: Optional SF Symbol system name for icon.
    ///   - isEnabled: Whether the item is enabled (default true).
    ///   - isSelected: Whether the item is selected (default false).
    ///   - action: The closure to call when tapped.
    public init(
        id: String,
        title: String,
        iconSystemName: String? = nil,
        isEnabled: Bool = true,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.action = action
    }
}

/// A reusable anchored popover menu to replace Apple's default glass menu.
///
/// This menu displays a list of selectable items anchored relative to a provided rectangle
/// in global coordinates. It supports disabled and selected states, automatically clamps
/// position to screen bounds, and dims the background to dismiss on tap.
///
/// The menu appears and disappears with a smooth opacity transition and avoids scale
/// or other animations to reduce flashing.
///
/// The content is scrollable if it exceeds the specified maximum height, and the layout
/// is stable with a rounded rectangle background, soft stroke, and shadow.
///
/// Accessibility:
/// - Each item has an accessibility label equal to its title.
/// - Selected items expose the selected trait.
///
public struct CSAnchoredMenu: View {
    @Binding private var isPresented: Bool
    private let anchorRect: CGRect
    private let items: [CSAnchoredMenuItem]
    private let preferredWidth: CGFloat
    private let maxHeight: CGFloat
    private let edgePadding: CGFloat

    @State private var menuSize: CGSize = .zero
    @State private var screenBounds: CGRect = .zero

    /// Creates a new anchored menu.
    ///
    /// - Parameters:
    ///   - isPresented: Binding controlling whether the menu is visible.
    ///   - anchorRect: The rectangle in global coordinates to anchor the menu to.
    ///   - items: The menu items to display.
    ///   - preferredWidth: The preferred fixed width of the menu. Default 260.
    ///   - maxHeight: The maximum height of the menu before scrolling occurs. Default 320.
    ///   - edgePadding: Padding from screen edges to clamp the menu position. Default 14.
    public init(
        isPresented: Binding<Bool>,
        anchorRect: CGRect,
        items: [CSAnchoredMenuItem],
        preferredWidth: CGFloat = 260,
        maxHeight: CGFloat = 320,
        edgePadding: CGFloat = 14
    ) {
        self._isPresented = isPresented
        self.anchorRect = anchorRect
        self.items = items
        self.preferredWidth = preferredWidth
        self.maxHeight = maxHeight
        self.edgePadding = edgePadding
    }

    public var body: some View {
        GeometryReader { proxy in
            // Capture screen bounds from the geometry proxy once
            Color.clear.preference(key: ScreenBoundsPreferenceKey.self, value: proxy.frame(in: .global))
        }
        .onPreferenceChange(ScreenBoundsPreferenceKey.self) { bounds in
            screenBounds = bounds
        }
        .overlay(
            Group {
                if isPresented {
                    backdrop
                        .transition(.opacity)
                        .animation(.linear(duration: 0.15), value: isPresented)
                        .accessibility(hidden: true)

                    menuContent
                        .frame(width: preferredWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            BackgroundShape()
                                .fill(.ultraThinMaterial, fillStyle: FillStyle(eoFill: false))
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(nsColor: .windowBackgroundColor))
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .opacity(isPresented ? 1 : 0)
                        .animation(.linear(duration: 0.15), value: isPresented)
                        .fixedSize()
                        .readSize { size in
                            menuSize = size
                        }
                        .position(menuPosition())
                        .transaction { $0.animation = nil }
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(.isModal)
                }
            }
        )
        .edgesIgnoringSafeArea(.all)
    }

    @ViewBuilder
    private var backdrop: some View {
        Color.black.opacity(0.24)
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.linear(duration: 0.15)) {
                    isPresented = false
                }
            }
            .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private var menuContent: some View {
        ScrollView(showsIndicators: true) {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    let isEnabled = item.isEnabled
                    Button(action: {
                        if isEnabled {
                            item.action()
                            withAnimation(.linear(duration: 0.15)) {
                                isPresented = false
                            }
                        }
                    }) {
                        HStack(spacing: 12) {
                            if item.isSelected {
                                Image(systemName: "checkmark")
                                    .imageScale(.small)
                                    .foregroundColor(Color.accentColor)
                                    .frame(width: 18)
                            } else {
                                // Reserve space for alignment
                                Color.clear.frame(width: 18)
                            }
                            if let iconName = item.iconSystemName {
                                Image(systemName: iconName)
                                    .frame(width: 18)
                                    .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.5))
                            }
                            Text(item.title)
                                .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                    }
                    .disabled(!isEnabled)
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(item.isSelected ? .isSelected : [])
                    .transaction { $0.animation = nil }
                }
            }
            .frame(maxHeight: maxHeight)
        }
        .transaction { $0.animation = nil }
    }

    /// Computes the menu position anchored relative to the anchor rect and clamped to screen bounds.
    /// Prefers positioning below the anchor rect, falls back above if insufficient space.
    private func menuPosition() -> CGPoint {
        guard screenBounds.width > 0 && screenBounds.height > 0 else {
            return CGPoint(x: anchorRect.midX, y: anchorRect.maxY)
        }
        let safeAnchor = safeAnchorRect(anchorRect, within: screenBounds)

        // Horizontal position: center aligned to anchorRect, clamped within screen edges with edgePadding
        let halfMenuWidth = preferredWidth / 2
        var x = safeAnchor.midX
        x = max(screenBounds.minX + edgePadding + halfMenuWidth, x)
        x = min(screenBounds.maxX - edgePadding - halfMenuWidth, x)

        // Vertical position: prefer below anchorRect, if no space place above
        let belowY = safeAnchor.maxY + menuSize.height / 2
        let aboveY = safeAnchor.minY - menuSize.height / 2

        // Check if menu fits below
        let fitsBelow = belowY + menuSize.height / 2 <= screenBounds.maxY - edgePadding
        let fitsAbove = aboveY - menuSize.height / 2 >= screenBounds.minY + edgePadding

        let y: CGFloat
        if fitsBelow {
            y = belowY
        } else if fitsAbove {
            y = aboveY
        } else {
            // Clamp vertically inside screen bounds
            y = min(
                max(screenBounds.minY + edgePadding + menuSize.height / 2, belowY),
                screenBounds.maxY - edgePadding - menuSize.height / 2
            )
        }
        return CGPoint(x: x, y: y)
    }

    /// Adjusts the anchor rect so it lies fully or partially within the given bounds.
    /// This avoids positioning relative to completely off-screen anchors.
    private func safeAnchorRect(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        var adjusted = rect

        if rect.minX > bounds.maxX || rect.maxX < bounds.minX {
            adjusted.origin.x = bounds.midX - rect.width / 2
        } else if rect.minX < bounds.minX {
            adjusted.origin.x = bounds.minX
        } else if rect.maxX > bounds.maxX {
            adjusted.origin.x = bounds.maxX - rect.width
        }

        if rect.minY > bounds.maxY || rect.maxY < bounds.minY {
            adjusted.origin.y = bounds.midY - rect.height / 2
        } else if rect.minY < bounds.minY {
            adjusted.origin.y = bounds.minY
        } else if rect.maxY > bounds.maxY {
            adjusted.origin.y = bounds.maxY - rect.height
        }

        return adjusted
    }
}

private struct ScreenBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct BackgroundShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect)
    }
}

private extension View {
    /// Reads the size of the view into the given binding.
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
