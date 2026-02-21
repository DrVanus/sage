//
//  ConversationSyncService.swift
//  CryptoSage
//
//  Handles Firestore sync for AI chat conversations.
//  Syncs conversation metadata and recent messages across devices.
//
//  FIRESTORE SYNC: When user is authenticated, conversations sync to Firestore
//  for cross-device consistency. Falls back to local-only when not authenticated.
//

import Foundation
import Combine
import FirebaseFirestore
import os

/// Service for syncing conversations to Firestore
/// Note: Due to Firestore document size limits (1MB), we sync:
/// - All conversation metadata (id, title, pinned, createdAt)
/// - Last 50 messages per conversation (truncated)
/// - Maximum 30 conversations total
@MainActor
final class ConversationSyncService: ObservableObject {
    static let shared = ConversationSyncService()
    
    // MARK: - Configuration
    
    /// Maximum messages to sync per conversation (Firestore size limit)
    private let maxMessagesPerConversation = 50
    
    /// Maximum conversations to sync (to manage Firestore costs)
    private let maxConversationsToSync = 30
    
    // MARK: - Firestore
    
    private let db = Firestore.firestore()
    private var firestoreListener: ListenerRegistration?
    private var isApplyingFirestoreUpdate = false
    private let logger = Logger(subsystem: "CryptoSage", category: "ConversationSyncService")
    
    deinit {
        firestoreListener?.remove()
    }
    
    /// Whether Firestore sync is currently active
    @Published private(set) var isFirestoreSyncActive: Bool = false
    
    /// Callback when conversations are updated from Firestore
    var onConversationsUpdated: (([Conversation]) -> Void)?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start listening to Firestore for conversation changes if user is authenticated
    func startFirestoreSyncIfAuthenticated() {
        guard AuthenticationManager.shared.isAuthenticated,
              let userId = AuthenticationManager.shared.currentUser?.id else {
            logger.debug("💬 [ConversationSync] Not authenticated, skipping Firestore sync")
            return
        }
        
        startFirestoreListener(userId: userId)
    }
    
    /// Stop Firestore listener
    func stopFirestoreSync() {
        firestoreListener?.remove()
        firestoreListener = nil
        isFirestoreSyncActive = false
        hasCompletedInitialFetch = false
        logger.info("💬 [ConversationSync] Stopped Firestore conversations sync")
    }
    
    /// Sync conversations to Firestore
    /// Call this after saving conversations locally
    func syncConversations(_ conversations: [Conversation]) {
        // Don't sync if this change came from Firestore (prevent loop)
        guard !isApplyingFirestoreUpdate else { return }
        
        guard AuthenticationManager.shared.isAuthenticated,
              let userId = AuthenticationManager.shared.currentUser?.id else {
            return
        }
        
        syncToFirestore(conversations: conversations, userId: userId)
    }
    
    // MARK: - Private Methods
    
    /// Whether we have completed the initial server fetch after sign-in.
    private var hasCompletedInitialFetch = false
    /// Last applied snapshot payload hash to suppress duplicate initial/server events.
    private var lastAppliedPayloadHash: Int?
    
    private func startFirestoreListener(userId: String) {
        guard firestoreListener == nil else {
            logger.debug("💬 [ConversationSync] Firestore listener already active")
            return
        }
        
        logger.info("💬 [ConversationSync] Starting Firestore conversations sync for user \(userId)")
        
        let conversationsRef = db.collection("users").document(userId).collection("conversations").document("chatHistory")
        
        // ── Step 1: Explicit server fetch on sign-in ──
        hasCompletedInitialFetch = false
        
        conversationsRef.getDocument(source: .server) { [weak self] snapshot, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.hasCompletedInitialFetch = true
                
                if let error = error {
                    self.logger.error("💬 [ConversationSync] Initial server fetch failed: \(error.localizedDescription)")
                } else if let snapshot = snapshot {
                    self.isFirestoreSyncActive = true
                    self.applyFirestoreSnapshot(snapshot, userId: userId)
                }
            }
        }
        
        // ── Step 2: Real-time listener for ongoing changes ──
        firestoreListener = conversationsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("💬 [ConversationSync] Firestore listener error: \(error.localizedDescription)")
                // MEMORY FIX v4: Stop listener on permission errors to prevent Firestore SDK
                // from retrying endlessly and consuming memory on each retry attempt.
                if error.localizedDescription.contains("Missing or insufficient permissions") {
                    self.logger.warning("💬 [ConversationSync] Stopping listener due to permission error")
                    self.firestoreListener?.remove()
                    self.firestoreListener = nil
                }
                return
            }
            
            guard let snapshot = snapshot else { return }
            
            Task { @MainActor in
                // PERFORMANCE FIX: Defer Firestore updates during scroll
                // Conversation sync can wait until scroll ends
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else {
                    // Re-queue after short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        Task { @MainActor in
                            self?.isFirestoreSyncActive = true
                            self?.applyFirestoreSnapshot(snapshot, userId: userId)
                        }
                    }
                    return
                }
                
                self.isFirestoreSyncActive = true
                self.applyFirestoreSnapshot(snapshot, userId: userId)
            }
        }
    }
    
    private func applyFirestoreSnapshot(_ snapshot: DocumentSnapshot, userId: String) {
        guard snapshot.exists, let data = snapshot.data() else {
            // Document doesn't exist yet - will be created on first save
            logger.info("💬 [ConversationSync] No existing conversations in Firestore")
            return
        }
        
        isApplyingFirestoreUpdate = true
        defer { isApplyingFirestoreUpdate = false }
        
        // Decode conversations from Firestore
        guard let conversationsData = data["conversations"] as? [[String: Any]] else {
            logger.warning("💬 [ConversationSync] Invalid conversations format in Firestore")
            return
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: conversationsData, options: [.sortedKeys])
            let payloadHash = jsonData.hashValue
            if let lastAppliedPayloadHash, lastAppliedPayloadHash == payloadHash {
                logger.debug("💬 [ConversationSync] Skipping duplicate snapshot payload")
                return
            }
            lastAppliedPayloadHash = payloadHash

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let decoded = try decoder.decode([Conversation].self, from: jsonData)
            
            logger.info("💬 [ConversationSync] Loaded \(decoded.count) conversations from Firestore")
            
            // Notify the view to update
            onConversationsUpdated?(decoded)
            
        } catch {
            logger.warning("💬 [ConversationSync] Failed to decode conversations: \(error.localizedDescription)")
        }
    }
    
    private func syncToFirestore(conversations: [Conversation], userId: String) {
        let conversationsRef = db.collection("users").document(userId).collection("conversations").document("chatHistory")
        
        // Prepare conversations for Firestore
        // Limit to most recent conversations and truncate messages
        let sortedConversations = conversations.sorted { 
            ($0.messages.last?.timestamp ?? $0.createdAt) > ($1.messages.last?.timestamp ?? $1.createdAt)
        }
        
        let limitedConversations = Array(sortedConversations.prefix(maxConversationsToSync))
        
        let truncatedConversations: [Conversation] = limitedConversations.map { convo in
            var truncated = convo
            // Keep only the most recent messages
            if truncated.messages.count > maxMessagesPerConversation {
                truncated.messages = Array(truncated.messages.suffix(maxMessagesPerConversation))
            }
            // Remove image data (too large for Firestore, kept locally)
            truncated.messages = truncated.messages.map { msg in
                var cleanMsg = msg
                cleanMsg.imageData = nil  // Don't sync binary image data
                return cleanMsg
            }
            return truncated
        }
        
        // Convert to Firestore-compatible format
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let jsonData = try encoder.encode(truncatedConversations)
            guard let conversationsArray = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                logger.error("💬 [ConversationSync] Failed to serialize conversations")
                return
            }
            
            let data: [String: Any] = [
                "conversations": conversationsArray,
                "conversationCount": truncatedConversations.count,
                "updatedAt": FieldValue.serverTimestamp(),
                "version": FieldValue.increment(Int64(1))
            ]
            
            conversationsRef.setData(data, merge: true) { [weak self] error in
                if let error = error {
                    self?.logger.error("💬 [ConversationSync] Failed to sync to Firestore: \(error.localizedDescription)")
                } else {
                    self?.logger.debug("💬 [ConversationSync] Synced \(truncatedConversations.count) conversations to Firestore")
                }
            }
        } catch {
            logger.error("💬 [ConversationSync] Failed to encode conversations: \(error.localizedDescription)")
        }
    }
}
