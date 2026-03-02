import SwiftUI

extension Conversation {
    var _id: UUID { id }
    var lastActivityDate: Date { lastMessageDate ?? createdAt }
}

struct ConversationHistoryView: View {
    // Passed in from parent
    var conversations: [Conversation]
    
    let onSelectConversation: (Conversation) -> Void
    let onNewChat: () -> Void
    let onDeleteConversation: (Conversation) -> Void
    let onRenameConversation: (Conversation, String) -> Void
    let onTogglePin: (Conversation) -> Void
    
    // Local state for searching & rename popovers
    @State private var searchText: String = ""
    @State private var conversationToRename: Conversation? = nil
    @State private var newTitle: String = ""
    
    // Whether the search bar is visible
    @State private var showSearch: Bool = false
    @FocusState private var isSearchFocused: Bool
    
    // Color scheme for adaptive light/dark mode
    @Environment(\.colorScheme) private var colorScheme
    
    // Adaptive background gradient
    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(red: 0.07, green: 0.07, blue: 0.07)]),
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.97),
                    Color(red: 0.94, green: 0.95, blue: 0.96)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Adaptive background gradient
                backgroundGradient
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Toggleable search bar
                    if showSearch {
                        searchBar()
                            .transition(.opacity)
                            .animation(.easeInOut, value: showSearch)
                    }
                    
                    conversationList()
                }
                
                // Floating "New Chat" button with premium gold styling - adaptive for light/dark
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: onNewChat) {
                            let isDark = colorScheme == .dark
                            ZStack {
                                // Base gold gradient
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: isDark
                                                ? [BrandColors.goldLight, BrandColors.goldBase]
                                                : [BrandColors.goldBase, BrandColors.goldDark],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                // Gloss highlight for premium glass feel
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(isDark ? 0.30 : 0.40), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                                
                                // Plus icon with luminous glow
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(isDark ? .black.opacity(0.88) : .white.opacity(0.95))
                            }
                            .frame(width: 54, height: 54)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: isDark
                                                ? [BrandColors.goldLight.opacity(0.6), BrandColors.goldBase.opacity(0.2)]
                                                : [BrandColors.goldDark.opacity(0.40), BrandColors.goldBase.opacity(0.15)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: isDark ? 1 : 1.2
                                    )
                            )
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            // Single magnifying glass button toggles search
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.easeInOut) {
                            showSearch.toggle()
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .imageScale(.large)
                    }
                    .foregroundColor(DS.Adaptive.textPrimary)
                }
            })
        }
        .presentationDragIndicator(.visible)
        // LIGHT MODE FIX: Ensure navigation bar fully adapts to light/dark mode.
        // Previously the header appeared black in light mode because toolbarColorScheme was missing.
        .toolbarBackground(DS.Adaptive.background.opacity(0.9), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .presentationBackground(DS.Adaptive.background)
        // Rename alert
        .alert("Rename Conversation",
               isPresented: Binding<Bool>(
                get: { conversationToRename != nil },
                set: { if !$0 { conversationToRename = nil } }
               ),
               actions: {
                   TextField("New Title", text: $newTitle)
                   Button("Save", action: renameConfirmed)
                   Button("Cancel", role: .cancel) {}
               },
               message: {
                   Text("Enter a new title:")
               }
        )
    }
}

// MARK: - Subviews
extension ConversationHistoryView {
    
    private func searchBar() -> some View {
        let isDark = colorScheme == .dark
        return HStack {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DS.Adaptive.textTertiary)
                TextField("Search Conversations", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            .padding(10)
            .contentShape(Rectangle())
            .onTapGesture {
                isSearchFocused = true
            }
            .background(DS.Adaptive.chipBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(BrandColors.goldLight.opacity(isDark ? 0.3 : 0.25), lineWidth: isDark ? 1 : 0.5)
            )
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .padding(.bottom, 4)
    }
    
    private func conversationList() -> some View {
        // Filter by search
        let filtered = conversations.filter { convo in
            searchText.isEmpty ||
            convo.title.localizedCaseInsensitiveContains(searchText)
        }
        
        let pinnedConvos = filtered.filter { $0.pinned }
        let unpinnedConvos = filtered.filter { !$0.pinned }
        
        let pinnedSorted = pinnedConvos.sorted { ($0.lastMessageDate ?? $0.createdAt) > ($1.lastMessageDate ?? $1.createdAt) }
        let unpinnedSorted = unpinnedConvos.sorted { ($0.lastMessageDate ?? $0.createdAt) > ($1.lastMessageDate ?? $1.createdAt) }
        
        return List {
            if !pinnedSorted.isEmpty {
                Section(header: pinnedHeader()) {
                    ForEach(pinnedSorted, id: \._id) { convo in
                        conversationCell(convo)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            
            if !unpinnedSorted.isEmpty {
                if !pinnedSorted.isEmpty {
                    Section(header: recentHeader()) {
                        ForEach(unpinnedSorted, id: \._id) { convo in
                            conversationCell(convo)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    // No pinned section; show recent conversations without a redundant header
                    ForEach(unpinnedSorted, id: \._id) { convo in
                        conversationCell(convo)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
    
    private func pinnedHeader() -> some View {
        HStack {
            Text("PINNED")
                .foregroundColor(BrandColors.goldLight)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.vertical, 4)
        .background(Color.clear)
    }
    
    private func recentHeader() -> some View {
        HStack {
            Text("RECENT")
                .foregroundColor(DS.Adaptive.textSecondary)
                .font(.caption)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.vertical, 4)
        .background(Color.clear)
    }
    
    private func conversationCell(_ convo: Conversation) -> some View {
        let preview = convo.messages.last?.text ?? ""
        let date = convo.lastActivityDate
        return HStack(alignment: .center, spacing: 12) {
            // Leading pin indicator when pinned
            if convo.pinned {
                Image(systemName: "pin.fill")
                    .foregroundColor(BrandColors.goldLight)
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(convo.title.isEmpty ? "Untitled Chat" : convo.title)
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if !preview.isEmpty {
                    Text(preview)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(relativeString(for: date))
                .foregroundColor(DS.Adaptive.textTertiary)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onSelectConversation(convo) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDeleteConversation(convo) } label: { Label("Delete", systemImage: "trash") }
            Button { conversationToRename = convo; newTitle = convo.title } label: { Label("Rename", systemImage: "pencil") }.tint(.blue)
            Button { onTogglePin(convo) } label: {
                Label(convo.pinned ? "Unpin" : "Pin", systemImage: convo.pinned ? "pin.slash" : "pin.fill")
            }.tint(BrandColors.goldBase)
        }
        .contextMenu {
            Button(convo.pinned ? "Unpin" : "Pin") { onTogglePin(convo) }
            Button("Rename") { conversationToRename = convo; newTitle = convo.title }
            Button("Delete", role: .destructive) { onDeleteConversation(convo) }
        }
    }
    
    private func renameConfirmed() {
        guard let convo = conversationToRename else { return }
        onRenameConversation(convo, newTitle)
        conversationToRename = nil
        newTitle = ""
    }
    
    private func relativeString(for date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
