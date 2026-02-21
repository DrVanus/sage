//
//  UsernameGenerator.swift
//  CryptoSage
//
//  Generates unique, memorable usernames for new users.
//  Uses adjective + animal combinations with collision detection.
//

import Foundation

// MARK: - Username Generator

/// Generates unique, memorable usernames for new users
public struct UsernameGenerator {
    
    // MARK: - Word Lists
    
    /// 60 trading/crypto-themed adjectives
    public static let adjectives: [String] = [
        // Speed/Action
        "Swift", "Quick", "Rapid", "Flash", "Turbo",
        "Agile", "Nimble", "Speedy", "Blazing", "Lightning",
        
        // Strength/Power
        "Bold", "Mighty", "Strong", "Fierce", "Epic",
        "Iron", "Steel", "Titan", "Power", "Ultra",
        
        // Precious/Value
        "Golden", "Diamond", "Crystal", "Silver", "Platinum",
        "Emerald", "Ruby", "Jade", "Pearl", "Onyx",
        
        // Nature/Elements
        "Storm", "Thunder", "Frost", "Solar", "Lunar",
        "Cosmic", "Nova", "Stellar", "Aurora", "Nebula",
        
        // Character/Style
        "Shadow", "Silent", "Stealth", "Mystic", "Zen",
        "Wise", "Sage", "Noble", "Royal", "Prime",
        
        // Crypto/Trading
        "Crypto", "Digital", "Cyber", "Alpha", "Apex",
        "Peak", "Summit", "Rising", "Bullish", "Quantum"
    ]
    
    /// 60 animals (mix of trading-relevant and cool animals)
    public static let animals: [String] = [
        // Trading Animals
        "Bull", "Bear", "Whale", "Shark", "Wolf",
        "Fox", "Hawk", "Eagle", "Falcon", "Raven",
        
        // Powerful Animals
        "Lion", "Tiger", "Panther", "Jaguar", "Leopard",
        "Dragon", "Phoenix", "Griffin", "Hydra", "Titan",
        
        // Swift Animals
        "Cheetah", "Gazelle", "Hare", "Viper", "Cobra",
        "Lynx", "Puma", "Coyote", "Jackal", "Otter",
        
        // Marine Animals
        "Dolphin", "Kraken", "Manta", "Marlin", "Barracuda",
        "Stingray", "Sailfish", "Swordfish", "Piranha", "Moray",
        
        // Wise/Mystical
        "Owl", "Sphinx", "Serpent", "Roc", "Chimera",
        "Basilisk", "Wyvern", "Behemoth", "Leviathan", "Colossus",
        
        // Other Cool Animals
        "Rhino", "Gorilla", "Wolverine", "Badger", "Mongoose",
        "Scorpion", "Mantis", "Tarantula", "Condor", "Osprey"
    ]
    
    /// Additional suffix words for even more combinations
    public static let suffixes: [String] = [
        "Pro", "Max", "Prime", "Elite", "Master",
        "King", "Lord", "Chief", "Boss", "Ace"
    ]
    
    // MARK: - Generation Methods
    
    /// Generate a random username (Adjective + Animal format)
    /// - Returns: A username like "SwiftFox" or "BoldWhale"
    public static func generate() -> String {
        let adjective = adjectives.randomElement() ?? "Swift"
        let animal = animals.randomElement() ?? "Fox"
        return "\(adjective)\(animal)"
    }
    
    /// Generate a username with a numeric suffix for uniqueness
    /// - Parameter suffix: Optional specific suffix, or random 4-digit if nil
    /// - Returns: A username like "SwiftFox3847"
    public static func generateWithSuffix(_ suffix: Int? = nil) -> String {
        let base = generate()
        let numericSuffix = suffix ?? Int.random(in: 1000...9999)
        return "\(base)\(numericSuffix)"
    }
    
    /// Generate a username with a word suffix
    /// - Returns: A username like "SwiftFoxPro"
    public static func generateWithWordSuffix() -> String {
        let base = generate()
        let suffix = suffixes.randomElement() ?? "Pro"
        return "\(base)\(suffix)"
    }
    
    /// Generate multiple username suggestions
    /// - Parameter count: Number of suggestions to generate
    /// - Returns: Array of unique username suggestions
    public static func generateSuggestions(count: Int = 5) -> [String] {
        var suggestions = Set<String>()
        
        // Add some base combinations
        while suggestions.count < count / 2 {
            suggestions.insert(generate())
        }
        
        // Add some with suffixes
        while suggestions.count < count {
            if Bool.random() {
                suggestions.insert(generateWithSuffix())
            } else {
                suggestions.insert(generateWithWordSuffix())
            }
        }
        
        return Array(suggestions)
    }
    
    /// Generate a unique username, checking against existing usernames
    /// - Parameter existingUsernames: Set of usernames that are already taken
    /// - Returns: A guaranteed unique username
    public static func generateUnique(existingUsernames: Set<String>) -> String {
        // Try base combination first (up to 10 attempts)
        for _ in 0..<10 {
            let username = generate().lowercased()
            if !existingUsernames.contains(username) {
                return username
            }
        }
        
        // If base combinations are taken, add numeric suffix
        var attempts = 0
        while attempts < 100 {
            let username = generateWithSuffix().lowercased()
            if !existingUsernames.contains(username) {
                return username
            }
            attempts += 1
        }
        
        // Fallback: use UUID suffix (guaranteed unique)
        let base = generate().lowercased()
        let uuid = UUID().uuidString.prefix(8).lowercased()
        return "\(base)_\(uuid)"
    }
    
    // MARK: - Validation
    
    /// Validate a username format
    /// - Parameter username: The username to validate
    /// - Returns: Validation result with any errors
    public static func validate(_ username: String) -> UsernameValidationResult {
        var errors: [UsernameValidationError] = []
        
        // Length check
        if username.count < 3 {
            errors.append(.tooShort)
        }
        if username.count > 20 {
            errors.append(.tooLong)
        }
        
        // Character check (alphanumeric and underscores only)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if username.unicodeScalars.contains(where: { !allowedCharacters.contains($0) }) {
            errors.append(.invalidCharacters)
        }
        
        // Must start with a letter
        if let first = username.first, !first.isLetter {
            errors.append(.mustStartWithLetter)
        }
        
        // Check for offensive words (basic list)
        let lowercased = username.lowercased()
        let blockedWords = ["admin", "moderator", "official", "support", "cryptosage", "system"]
        if blockedWords.contains(where: { lowercased.contains($0) }) {
            errors.append(.reservedWord)
        }
        
        return UsernameValidationResult(isValid: errors.isEmpty, errors: errors)
    }
    
    /// Check if a username is available (would need Firebase integration)
    /// - Parameter username: The username to check
    /// - Parameter completion: Callback with availability result
    public static func checkAvailability(
        _ username: String,
        completion: @escaping (Bool) -> Void
    ) {
        // TODO: Implement Firebase check
        // For now, always return available
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            completion(true)
        }
    }
    
    // MARK: - Statistics
    
    /// Total number of base combinations (adjectives × animals)
    public static var totalBaseCombinations: Int {
        adjectives.count * animals.count
    }
    
    /// Total combinations with numeric suffixes
    public static var totalWithNumericSuffix: Int {
        totalBaseCombinations * 9000 // 1000-9999
    }
    
    /// Total combinations with word suffixes
    public static var totalWithWordSuffix: Int {
        totalBaseCombinations * suffixes.count
    }
    
    /// Total possible unique usernames
    public static var totalPossibleUsernames: Int {
        totalBaseCombinations + totalWithNumericSuffix + totalWithWordSuffix
    }
}

// MARK: - Validation Result

/// Result of username validation
public struct UsernameValidationResult {
    public let isValid: Bool
    public let errors: [UsernameValidationError]
    
    public var errorMessage: String? {
        guard !isValid, let firstError = errors.first else { return nil }
        return firstError.message
    }
}

/// Username validation errors
public enum UsernameValidationError: String, CaseIterable {
    case tooShort
    case tooLong
    case invalidCharacters
    case mustStartWithLetter
    case reservedWord
    case alreadyTaken
    
    public var message: String {
        switch self {
        case .tooShort:
            return "Username must be at least 3 characters"
        case .tooLong:
            return "Username must be 20 characters or less"
        case .invalidCharacters:
            return "Username can only contain letters, numbers, and underscores"
        case .mustStartWithLetter:
            return "Username must start with a letter"
        case .reservedWord:
            return "This username contains a reserved word"
        case .alreadyTaken:
            return "This username is already taken"
        }
    }
}

// MARK: - Username Suggestions View Model

/// View model for username selection/editing
@MainActor
public class UsernameViewModel: ObservableObject {
    @Published public var username: String = ""
    @Published public var suggestions: [String] = []
    @Published public var isChecking: Bool = false
    @Published public var isAvailable: Bool? = nil
    @Published public var validationError: String? = nil
    
    private var checkTask: Task<Void, Never>?
    
    public init() {
        generateSuggestions()
    }
    
    /// Generate new username suggestions
    public func generateSuggestions() {
        suggestions = UsernameGenerator.generateSuggestions(count: 6)
    }
    
    /// Select a suggested username
    public func selectSuggestion(_ suggestion: String) {
        username = suggestion.lowercased()
        validateAndCheck()
    }
    
    /// Validate the current username and check availability
    public func validateAndCheck() {
        // Cancel previous check
        checkTask?.cancel()
        
        // Reset state
        isAvailable = nil
        validationError = nil
        
        // Validate format
        let validation = UsernameGenerator.validate(username)
        if !validation.isValid {
            validationError = validation.errorMessage
            return
        }
        
        // Check availability
        isChecking = true
        checkTask = Task {
            // Simulate network delay
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            guard !Task.isCancelled else { return }
            
            // TODO: Real Firebase check
            UsernameGenerator.checkAvailability(username) { [weak self] available in
                guard let self = self else { return }
                self.isChecking = false
                self.isAvailable = available
                if !available {
                    self.validationError = UsernameValidationError.alreadyTaken.message
                }
            }
        }
    }
    
    /// Generate a random unique username
    public func generateRandom() {
        username = UsernameGenerator.generate().lowercased()
        validateAndCheck()
    }
}
