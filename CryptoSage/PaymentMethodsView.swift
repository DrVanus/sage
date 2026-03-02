import SwiftUI

/// A single PaymentMethod model
struct PaymentMethod: Identifiable {
    var id = UUID()
    var name: String
    var details: String
    var isPreferred: Bool = false
    
    // NEW FIELDS for optional API-based connections
    var apiKey: String?
    var secretKey: String?
    var isConnected: Bool = false
}

/// Your existing picker view.
struct EnhancedPaymentMethodPickerView: View {
    // DEPRECATED FIX: Use dismiss instead of presentationMode
    @Environment(\.dismiss) private var dismiss
    
    // The currently selected PaymentMethod (bound from TradeView or wherever).
    @Binding var currentMethod: PaymentMethod
    
    // Callback: when user picks or changes the method
    var onSelect: (PaymentMethod) -> Void
    
    // Local list of PaymentMethods. Replace with real data, or store in a ViewModel.
    @State private var allMethods: [PaymentMethod] = [
        PaymentMethod(name: "Coinbase", details: "Coinbase Exchange"),
        PaymentMethod(name: "Binance", details: "Binance Exchange"),
        PaymentMethod(name: "Kraken", details: "Kraken Exchange"),
        PaymentMethod(name: "Wallet USD", details: "Local USD wallet"),
        PaymentMethod(name: "Wallet USDT", details: "Local USDT wallet")
    ]
    
    // Searching
    @State private var searchText: String = ""
    
    // Renaming
    @State private var renameTarget: PaymentMethod? = nil
    @State private var renameText: String = ""
    @State private var showRenameSheet: Bool = false
    
    // Adding a new PaymentMethod
    @State private var showAddSheet: Bool = false
    
    // Connecting/Disconnecting
    @State private var connectTarget: PaymentMethod? = nil
    @State private var showConnectSheet: Bool = false
    @State private var showConnectionResultAlert: Bool = false
    @State private var connectionResultMessage: String = ""
    
    // Filtered list based on search
    var filteredMethods: [PaymentMethod] {
        if searchText.isEmpty {
            return allMethods
        }
        return allMethods.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
            || $0.details.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                DS.Adaptive.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // SEARCH BAR
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search payment methods", text: $searchText)
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    .padding(8)
                    .background(DS.Adaptive.chipBackground)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // LIST OF METHODS
                    List {
                        ForEach(filteredMethods) { method in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    // Show a star if it's the preferred method
                                    HStack(spacing: 4) {
                                        Text(method.name)
                                            .foregroundColor(DS.Adaptive.textPrimary)
                                            .font(.headline)
                                        if method.isPreferred {
                                            Image(systemName: "star.fill")
                                                .foregroundColor(DS.Adaptive.gold)
                                                .font(.caption)
                                        }
                                    }
                                    Text(method.details)
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                }
                                Spacer()
                                // If this method is the currently selected one, show a check
                                if method.id == currentMethod.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(DS.Adaptive.gold)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                currentMethod = method
                                onSelect(method)
                                dismiss()
                            }
                            // SWIPE ACTIONS
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteMethod(method)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    renameTarget = method
                                    renameText = method.name
                                    showRenameSheet = true
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                                
                                Button {
                                    makePreferred(method)
                                } label: {
                                    Label("Preferred", systemImage: "star")
                                }
                                .tint(.yellow)
                                
                                if !method.isConnected {
                                    Button {
                                        connectMethod(method)
                                    } label: {
                                        Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                                    }
                                    .tint(.green)
                                } else {
                                    Button {
                                        testConnection(method)
                                    } label: {
                                        Label("Test", systemImage: "checkmark.seal")
                                    }
                                    .tint(.green)
                                    
                                    Button(role: .destructive) {
                                        disconnectMethod(method)
                                    } label: {
                                        Label("Disconnect", systemImage: "wifi.exclamationmark")
                                    }
                                }
                            }
                            .contextMenu {
                                Button("Make Preferred") {
                                    makePreferred(method)
                                }
                                Button("Rename") {
                                    renameTarget = method
                                    renameText = method.name
                                    showRenameSheet = true
                                }
                                Button(role: .destructive) {
                                    deleteMethod(method)
                                } label: {
                                    Text("Delete")
                                }
                                Divider()
                                if !method.isConnected {
                                    Button("Connect") {
                                        connectMethod(method)
                                    }
                                } else {
                                    Button("Test Connection") {
                                        testConnection(method)
                                    }
                                    Button("Disconnect", role: .destructive) {
                                        disconnectMethod(method)
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Select Payment Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(DS.Adaptive.gold)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundColor(DS.Adaptive.gold)
                }
            }
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
            // RENAME SHEET
            .sheet(isPresented: $showRenameSheet) {
                if let renameTarget = renameTarget {
                    RenamePaymentMethodView(
                        method: renameTarget,
                        initialText: renameText
                    ) { newName in
                        if let idx = allMethods.firstIndex(where: { $0.id == renameTarget.id }) {
                            allMethods[idx].name = newName
                        }
                    }
                }
            }
            // ADD SHEET
            .sheet(isPresented: $showAddSheet) {
                AddPaymentMethodView { name, details in
                    let newMethod = PaymentMethod(name: name, details: details)
                    allMethods.append(newMethod)
                }
            }
            // CONNECT SHEET
            .sheet(isPresented: $showConnectSheet) {
                if let connectTarget = connectTarget {
                    ConnectPaymentMethodView(method: connectTarget) { updated in
                        if let idx = allMethods.firstIndex(where: { $0.id == updated.id }) {
                            allMethods[idx] = updated
                        }
                    }
                }
            }
            // TEST CONNECTION ALERT
            .alert(isPresented: $showConnectionResultAlert) {
                Alert(title: Text("Connection Test"),
                      message: Text(connectionResultMessage),
                      dismissButton: .default(Text("OK")))
            }
        }
        .accentColor(.yellow)
    }
    
    // MARK: - Actions
    
    private func makePreferred(_ method: PaymentMethod) {
        for i in allMethods.indices {
            allMethods[i].isPreferred = false
        }
        if let idx = allMethods.firstIndex(where: { $0.id == method.id }) {
            allMethods[idx].isPreferred = true
        }
    }
    
    private func deleteMethod(_ method: PaymentMethod) {
        if let idx = allMethods.firstIndex(where: { $0.id == method.id }) {
            allMethods.remove(at: idx)
        }
    }
    
    private func connectMethod(_ method: PaymentMethod) {
        connectTarget = method
        showConnectSheet = true
    }
    
    private func disconnectMethod(_ method: PaymentMethod) {
        if let idx = allMethods.firstIndex(where: { $0.id == method.id }) {
            allMethods[idx].isConnected = false
            allMethods[idx].apiKey = nil
            allMethods[idx].secretKey = nil
        }
    }
    
    private func testConnection(_ method: PaymentMethod) {
        connectionResultMessage = "Connection to \(method.name) is successful!"
        showConnectionResultAlert = true
    }
}

/// A small sheet to rename a payment method.
struct RenamePaymentMethodView: View {
    let method: PaymentMethod
    @State var text: String
    var onSave: (String) -> Void
    // DEPRECATED FIX: Use dismiss instead of presentationMode
    @Environment(\.dismiss) private var dismiss
    
    init(method: PaymentMethod, initialText: String, onSave: @escaping (String) -> Void) {
        self.method = method
        self._text = State(initialValue: initialText)
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("New name", text: $text)
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// A small sheet to add a new payment method.
struct AddPaymentMethodView: View {
    // DEPRECATED FIX: Use dismiss instead of presentationMode
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var details: String = ""
    var onAdd: (String, String) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Payment Method Info")) {
                    TextField("Name", text: $name)
                    TextField("Details", text: $details)
                }
            }
            .navigationTitle("Add Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(name, details)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// A small sheet to collect API credentials to connect a payment method.
struct ConnectPaymentMethodView: View {
    // DEPRECATED FIX: Use dismiss instead of presentationMode
    @Environment(\.dismiss) private var dismiss
    var method: PaymentMethod
    var onConnect: (PaymentMethod) -> Void
    @State private var tempApiKey: String = ""
    @State private var tempSecretKey: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Connect to \(method.name)")) {
                    TextField("API Key", text: $tempApiKey)
                        .textContentType(.username)
                    SecureField("Secret Key", text: $tempSecretKey)
                }
                Section {
                    Button("Save") {
                        var updated = method
                        updated.apiKey = tempApiKey
                        updated.secretKey = tempSecretKey
                        updated.isConnected = true
                        onConnect(updated)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Connect \(method.name)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
