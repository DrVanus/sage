//
//  FavoritesManager.swift
//  CryptoSage
//
//  Created by DM on 6/3/25.
//
//  FIRESTORE SYNC: When user is authenticated, watchlist syncs to Firestore
//  for cross-device consistency. Falls back to local-only when not authenticated.
//

import Foundation
import Combine
import FirebaseFirestore
import os

/// Posted by FavoritesManager whenever a favorite is toggled (added or removed).
/// This notification fires synchronously on the main thread and is reliable even when
/// Combine-based `.onReceive` subscriptions are lost (e.g., LazyVStack view lifecycle).
extension Notification.Name {
    static let favoritesDidChange = Notification.Name("com.cryptosage.favoritesDidChange")
}

final class FavoritesManager: ObservableObject, @unchecked Sendable {
    // The single UserDefaults key under which we store the Set of IDs
    private let defaultsKey = "favoriteCoinIDs"
    private let orderKey = "favoriteCoinOrder"

    // Published set of IDs. Whenever this changes, SwiftUI views bound to it will update.
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var favoriteOrder: [String] = []
    /// Expose a read-only alias named `favorites` so views can bind to `favoriteIDs`.
    var favorites: Set<String> { favoriteIDs }
    
    // MARK: - Firestore Sync
    
    private let db = Firestore.firestore()
    private var firestoreListener: ListenerRegistration?
    private var isApplyingFirestoreUpdate = false  // Prevent sync loops
    private let logger = Logger(subsystem: "CryptoSage", category: "FavoritesManager")
    
    deinit {
        firestoreListener?.remove()
    }
    
    /// Whether Firestore sync is currently active
    @Published private(set) var isFirestoreSyncActive: Bool = false

    // Make it a shared singleton
    static let shared = FavoritesManager()

    private var cancellables = Set<AnyCancellable>()

    /// Emits the set of favoriteIDs only after a 0.5s pause, and only when it changes.
    var debouncedFavoriteIDs: AnyPublisher<Set<String>, Never> {
        $favoriteIDs
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private init() {
        loadFromDefaults()

        // PERFORMANCE FIX: Use debounced publisher for save/sync operations
        // The direct $favoriteIDs subscription was triggering immediate disk I/O and
        // Firestore syncs on every single change, causing UI stuttering during rapid updates.
        // The 500ms debounce batches rapid changes (e.g., bulk add/remove operations).
        debouncedFavoriteIDs
            .sink { [weak self] newSet in
                self?.saveToDefaults(newSet)
                self?.syncToFirestoreIfNeeded(newSet)
            }
            .store(in: &cancellables)

        // FIX: Removed redundant fetchWatchlistMarkets call. MarketViewModel already
        // subscribes to $favoriteIDs and calls loadWatchlistDataImmediate() which handles
        // all watchlist data loading. The result of fetchWatchlistMarkets here was assigned
        // to _ (unused), and the competing network request during the critical favorites-change
        // window added unnecessary load and potential race conditions.
        
        // Firestore sync startup is orchestrated by AuthenticationManager
        // to avoid duplicate listener bursts during app launch.
    }
    
    // MARK: - Firestore Sync Methods
    
    /// Start listening to Firestore for watchlist changes if user is authenticated
    func startFirestoreSyncIfAuthenticated() {
        Task { @MainActor in
            guard AuthenticationManager.shared.isAuthenticated,
                  let userId = AuthenticationManager.shared.currentUser?.id else {
                logger.debug("🔥 [FavoritesManager] Not authenticated, skipping Firestore sync")
                return
            }
            
            startFirestoreListener(userId: userId)
        }
    }
    
    /// Whether we have completed the initial server fetch after sign-in.
    private var hasCompletedInitialFetch = false
    
    /// Start Firestore listener for a specific user
    private func startFirestoreListener(userId: String) {
        guard firestoreListener == nil else {
            logger.debug("🔥 [FavoritesManager] Firestore listener already active")
            return
        }
        
        logger.info("🔥 [FavoritesManager] Starting Firestore watchlist sync for user \(userId)")
        
        let watchlistRef = db.collection("users").document(userId).collection("watchlist").document("favorites")
        
        // ── Step 1: Explicit server fetch on sign-in ──
        hasCompletedInitialFetch = false
        
        watchlistRef.getDocument(source: .server) { [weak self] snapshot, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.hasCompletedInitialFetch = true
                
                if let error = error {
                    self.logger.error("🔥 [FavoritesManager] Initial server fetch failed: \(error.localizedDescription)")
                } else if let snapshot = snapshot {
                    self.isFirestoreSyncActive = true
                    self.applyFirestoreSnapshot(snapshot)
                }
            }
        }
        
        // ── Step 2: Real-time listener for ongoing changes ──
        firestoreListener = watchlistRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("🔥 [FavoritesManager] Firestore listener error: \(error.localizedDescription)")
                // MEMORY FIX v4: Stop listener on permission errors to prevent Firestore SDK
                // from retrying endlessly and consuming memory on each retry attempt.
                if error.localizedDescription.contains("Missing or insufficient permissions") {
                    self.logger.warning("🔥 [FavoritesManager] Stopping listener due to permission error")
                    self.firestoreListener?.remove()
                    self.firestoreListener = nil
                }
                return
            }
            
            guard let snapshot = snapshot else { return }
            
            DispatchQueue.main.async {
                // Guard: Don't upload local data based on empty cache on fresh install
                if !snapshot.exists {
                    if snapshot.metadata.isFromCache || !self.hasCompletedInitialFetch {
                        self.logger.debug("🔥 [FavoritesManager] Ignoring empty snapshot (waiting for server)")
                        return
                    }
                }
                
                // PERFORMANCE FIX: Defer Firestore updates during scroll
                // Watchlist sync can wait until scroll ends
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else {
                    // Re-queue after short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.isFirestoreSyncActive = true
                        self?.applyFirestoreSnapshot(snapshot)
                    }
                    return
                }
                
                self.isFirestoreSyncActive = true
                self.applyFirestoreSnapshot(snapshot)
            }
        }
    }
    
    /// Stop Firestore listener
    func stopFirestoreSync() {
        firestoreListener?.remove()
        firestoreListener = nil
        isFirestoreSyncActive = false
        hasCompletedInitialFetch = false
        logger.info("🔥 [FavoritesManager] Stopped Firestore watchlist sync")
    }
    
    /// Fingerprint of last applied Firestore payload to suppress duplicate listener emissions.
    private var lastFirestoreSnapshotFingerprint: String?
    
    /// Apply changes from Firestore snapshot
    private func applyFirestoreSnapshot(_ snapshot: DocumentSnapshot) {
        guard snapshot.exists, let data = snapshot.data() else {
            // Document doesn't exist yet - upload local data
            logger.info("🔥 [FavoritesManager] Firestore watchlist document does not exist. Local favorites: \(self.favoriteIDs.count). Uploading local data.")
            uploadToFirestore()
            return
        }
        
        logger.info("🔥 [FavoritesManager] Received Firestore snapshot. Document fields: \(data.keys.sorted().joined(separator: ", "))")
        
        guard let coinIds = data["coinIds"] as? [String],
              let order = data["order"] as? [String] else {
            logger.warning("🔥 [FavoritesManager] Invalid Firestore watchlist format. Data keys: \(data.keys.sorted())")
            return
        }
        
        // Firestore often emits the same payload twice (initial fetch + listener or metadata updates).
        // Skip no-op payloads to prevent duplicate work/logging during startup.
        let snapshotFingerprint = "\(coinIds.joined(separator: ","))|\(order.joined(separator: ","))"
        if snapshotFingerprint == lastFirestoreSnapshotFingerprint {
            logger.debug("🔥 [FavoritesManager] Duplicate Firestore snapshot skipped")
            return
        }
        lastFirestoreSnapshotFingerprint = snapshotFingerprint
        
        logger.info("🔥 [FavoritesManager] Cloud watchlist: \(coinIds.count) coins. Local watchlist: \(self.favoriteIDs.count) coins.")
        
        // Prevent sync loop
        isApplyingFirestoreUpdate = true
        defer { isApplyingFirestoreUpdate = false }
        
        // Merge strategy: use server data as source of truth
        // (For more sophisticated merging, could compare timestamps)
        let newSet = Set(coinIds)
        if newSet != favoriteIDs {
            let previousCount = favoriteIDs.count
            favoriteIDs = newSet
            logger.info("🔥 [FavoritesManager] Updated favorites from Firestore: \(coinIds.count) coins (was \(previousCount))")
        }
        
        if order != favoriteOrder {
            favoriteOrder = order
            normalizeOrder()
            logger.info("🔥 [FavoritesManager] Updated order from Firestore")
        }
        
        // Persist locally as well
        saveToDefaults(favoriteIDs)
    }
    
    /// Sync local changes to Firestore
    private func syncToFirestoreIfNeeded(_ favorites: Set<String>) {
        // Don't sync if this change came from Firestore (prevent loop)
        guard !isApplyingFirestoreUpdate else { return }
        
        // Capture values needed for Firestore write
        let order = favoriteOrder
        let favoritesArray = Array(favorites)
        
        // Access MainActor-isolated auth properties safely
        Task { @MainActor [weak self] in
            guard let self,
                  AuthenticationManager.shared.isAuthenticated,
                  let userId = AuthenticationManager.shared.currentUser?.id else {
                return
            }
            
            let watchlistRef = self.db.collection("users").document(userId).collection("watchlist").document("favorites")
            
            let data: [String: Any] = [
                "coinIds": favoritesArray,
                "order": order,
                "updatedAt": FieldValue.serverTimestamp(),
                "version": FieldValue.increment(Int64(1))
            ]
            
            do {
                try await watchlistRef.setData(data, merge: true)
                self.logger.debug("🔥 [FavoritesManager] Synced \(favoritesArray.count) favorites to Firestore")
            } catch {
                self.logger.error("🔥 [FavoritesManager] Failed to sync to Firestore: \(error.localizedDescription)")
            }
        }
    }

    /// Force upload local data to Firestore (used when document doesn't exist)
    private func uploadToFirestore() {
        // Capture values needed for Firestore write
        let favoritesArray = Array(favoriteIDs)
        let order = favoriteOrder

        // Access MainActor-isolated auth properties safely
        Task { @MainActor [weak self] in
            guard let self,
                  AuthenticationManager.shared.isAuthenticated,
                  let userId = AuthenticationManager.shared.currentUser?.id else {
                return
            }

            let watchlistRef = self.db.collection("users").document(userId).collection("watchlist").document("favorites")

            let data: [String: Any] = [
                "coinIds": favoritesArray,
                "order": order,
                "updatedAt": FieldValue.serverTimestamp(),
                "version": 1
            ]

            do {
                try await watchlistRef.setData(data)
                self.logger.info("🔥 [FavoritesManager] Uploaded local watchlist to Firestore")
            } catch {
                self.logger.error("🔥 [FavoritesManager] Failed to upload to Firestore: \(error.localizedDescription)")
            }
        }
    }

    private func loadFromDefaults() {
        let savedIDs = (UserDefaults.standard.array(forKey: defaultsKey) as? [String]) ?? []
        favoriteIDs = Set(savedIDs)
        if let savedOrder = UserDefaults.standard.array(forKey: orderKey) as? [String] {
            favoriteOrder = savedOrder
        } else {
            // Seed the order with the saved IDs in their stored order (or any order if none)
            favoriteOrder = savedIDs.isEmpty ? Array(favoriteIDs) : savedIDs
        }
        normalizeOrder()
    }

    private func saveToDefaults(_ set: Set<String>) {
        let array = Array(set)
        UserDefaults.standard.set(array, forKey: defaultsKey)
        normalizeOrder()
        UserDefaults.standard.set(favoriteOrder, forKey: orderKey)
    }

    private func normalizeOrder() {
        // Ensure favoriteOrder contains exactly the IDs in favoriteIDs, preserving order where possible
        let set = favoriteIDs
        var ordered: [String] = []
        var seen = Set<String>()
        for id in favoriteOrder where set.contains(id) {
            if !seen.contains(id) { ordered.append(id); seen.insert(id) }
        }
        // Append any IDs that are not yet in the order to the end
        for id in set where !seen.contains(id) { ordered.append(id); seen.insert(id) }
        favoriteOrder = ordered
    }

    // MARK: - Public API

    func isFavorite(coinID: String) -> Bool {
        favoriteIDs.contains(coinID)
    }

    func addToFavorites(coinID: String) {
        favoriteIDs.insert(coinID)
        if !favoriteOrder.contains(coinID) { favoriteOrder.append(coinID) }
        saveToDefaults(favoriteIDs)
    }

    func removeFromFavorites(coinID: String) {
        favoriteIDs.remove(coinID)
        favoriteOrder.removeAll { $0 == coinID }
        saveToDefaults(favoriteIDs)
    }

    func toggle(coinID: String) {
        if isFavorite(coinID: coinID) {
            removeFromFavorites(coinID: coinID)
        } else {
            addToFavorites(coinID: coinID)
        }
        // WATCHLIST INSTANT-SYNC: Post a NotificationCenter notification as a backup.
        // The Combine-based $favoriteIDs publisher is the primary mechanism, but its
        // .onReceive subscription in WatchlistSection can be lost if LazyVStack destroys
        // the view while the user is on another tab. NotificationCenter is reliable
        // regardless of view lifecycle and ensures the watchlist refreshes on tab switch.
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil,
                                        userInfo: ["coinID": coinID])
    }

    /// Alias for `removeFromFavorites(_:)` so callers can use `remove(coinID:)`
    func remove(coinID: String) {
        removeFromFavorites(coinID: coinID)
    }

    /// Return all favorite IDs as a Set<String>.
    func getAllIDs() -> Set<String> {
        return favoriteIDs
    }

    func getOrder() -> [String] { favoriteOrder }
    func index(of coinID: String) -> Int? { favoriteOrder.firstIndex(of: coinID) }

    /// Replace the favorite order with a new list of IDs (filtered to existing favorites) and persist it.
    func updateOrder(_ newOrder: [String]) {
        // Keep only IDs that are currently favorited, preserving their new order
        let filtered = newOrder.filter { favoriteIDs.contains($0) }
        var ordered: [String] = []
        var seen = Set<String>()
        for id in filtered where !seen.contains(id) { ordered.append(id); seen.insert(id) }
        // Append any remaining favorites that weren’t included, preserving their current relative order
        for id in favoriteOrder where favoriteIDs.contains(id) && !seen.contains(id) { ordered.append(id); seen.insert(id) }
        for id in favoriteIDs where !seen.contains(id) { ordered.append(id); seen.insert(id) }
        favoriteOrder = ordered
        // Persist order
        UserDefaults.standard.set(favoriteOrder, forKey: orderKey)
    }

    /// Convenience: mutate the order by moving rows like SwiftUI's onMove, then persist.
    func move(fromOffsets: IndexSet, toOffset: Int) {
        var arr = favoriteOrder.filter { favoriteIDs.contains($0) }
        arr.move(fromOffsets: fromOffsets, toOffset: toOffset)
        updateOrder(arr)
    }
}
