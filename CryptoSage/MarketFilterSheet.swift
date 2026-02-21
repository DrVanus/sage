//
//  MarketFilterSheet.swift
//  CryptoSage
//
//  Bottom sheet for market filtering - categories and sort options.
//  Fully adaptive for light/dark mode with premium styling.
//

import SwiftUI

struct MarketFilterSheet: View {
    @ObservedObject var viewModel: MarketViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Local state for preview before applying
    @State private var selectedCategory: MarketCategory
    @State private var selectedSortField: SortField
    @State private var selectedSortDirection: SortDirection
    
    init(viewModel: MarketViewModel) {
        self.viewModel = viewModel
        _selectedCategory = State(initialValue: viewModel.selectedCategory)
        _selectedSortField = State(initialValue: viewModel.sortField)
        _selectedSortDirection = State(initialValue: viewModel.sortDirection)
    }
    
    // MARK: - Adaptive Colors
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Page background
    private var pageBg: Color {
        isDark ? Color(red: 0.06, green: 0.06, blue: 0.07) : Color(red: 0.97, green: 0.97, blue: 0.96)
    }
    
    /// Section title color
    private var sectionTitle: Color {
        isDark ? .white : Color(red: 0.15, green: 0.15, blue: 0.15)
    }
    
    /// Subtitle / secondary text
    private var textSecondary: Color {
        isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.45)
    }
    
    /// Divider color
    private var dividerColor: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    
    /// Gold accent for selected states
    private var goldAccent: Color {
        isDark ? Color(red: 1.0, green: 0.85, blue: 0.05) : Color(red: 0.831, green: 0.686, blue: 0.216)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Category Section
                    categorySection
                    
                    // Premium divider
                    Rectangle()
                        .fill(dividerColor)
                        .frame(height: isDark ? 0.5 : 0.8)
                        .padding(.horizontal, 4)
                    
                    // Sort Section
                    sortSection
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .background(pageBg)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        resetFilters()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        applyFilters()
                        dismiss()
                    } label: {
                        Text("Apply")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isDark ? .black : Color(red: 0.30, green: 0.22, blue: 0.02))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(goldAccent)
                            )
                    }
                }
            }
            .toolbarBackground(pageBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(pageBg)
    }
    
    // MARK: - Category Section
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Category")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(sectionTitle)
            
            // Category chips in a wrapped flow layout
            FlowLayout(spacing: 10) {
                ForEach(MarketCategory.allCases, id: \.id) { category in
                    categoryChip(category)
                }
            }
        }
    }
    
    private func categoryChip(_ category: MarketCategory) -> some View {
        let isSelected = selectedCategory == category
        
        // Adaptive chip colors
        let chipBg: Color = {
            if isSelected {
                return goldAccent
            } else {
                return isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
            }
        }()
        
        let chipText: Color = {
            if isSelected {
                return isDark ? .black : Color(red: 0.30, green: 0.22, blue: 0.02)
            } else {
                return isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.70)
            }
        }()
        
        let chipStroke: Color = {
            if isSelected {
                return goldAccent.opacity(isDark ? 0.6 : 0.4)
            } else {
                return isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
            }
        }()
        
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(chipText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(chipBg)
            )
            .overlay(
                Capsule()
                    .stroke(chipStroke, lineWidth: isSelected ? (isDark ? 0.8 : 0.5) : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Sort Section
    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sort By")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(sectionTitle)
            
            // Sort field options
            VStack(spacing: 4) {
                ForEach(SortField.allCases, id: \.id) { field in
                    sortFieldRow(field)
                }
            }
            
            // Sort direction toggle
            HStack {
                Text("Direction")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(textSecondary)
                
                Spacer()
                
                // Custom segmented control for direction
                HStack(spacing: 0) {
                    directionButton("Descending", direction: .desc)
                    directionButton("Ascending", direction: .asc)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 0.5)
                )
            }
            .padding(.top, 8)
        }
    }
    
    private func directionButton(_ label: String, direction: SortDirection) -> some View {
        let isSelected = selectedSortDirection == direction
        
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSortDirection = direction
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundColor(
                    isSelected
                        ? (isDark ? .black : Color(red: 0.30, green: 0.22, blue: 0.02))
                        : textSecondary
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? goldAccent : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func sortFieldRow(_ field: SortField) -> some View {
        let isSelected = selectedSortField == field
        
        let rowBg: Color = {
            if isSelected {
                return isDark ? goldAccent.opacity(0.10) : goldAccent.opacity(0.08)
            } else {
                return .clear
            }
        }()
        
        let rowStroke: Color = isSelected ? goldAccent.opacity(isDark ? 0.25 : 0.18) : .clear
        
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSortField = field
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack {
                Text(field.rawValue)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? sectionTitle : textSecondary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(goldAccent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rowBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(rowStroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    private func applyFilters() {
        viewModel.selectedCategory = selectedCategory
        viewModel.sortField = selectedSortField
        viewModel.sortDirection = selectedSortDirection
    }
    
    private func resetFilters() {
        withAnimation {
            selectedCategory = .all
            selectedSortField = .marketCap
            selectedSortDirection = .desc
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Flow Layout for Chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                // Move to next line
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }
        
        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

#Preview {
    MarketFilterSheet(viewModel: MarketViewModel.shared)
        .preferredColorScheme(.dark)
}
