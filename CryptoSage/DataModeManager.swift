//
//  DataMode.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//

import SwiftUI
import Combine

/// Switch between .live and .mock at runtime (stored in UserDefaults)
enum DataMode: String {
  case live, mock
}

/// Observable manager for the current data mode
final class DataModeManager: ObservableObject {
  private let storedModeRaw: String
  @Published var mode: DataMode {
    didSet {
      UserDefaults.standard.set(mode.rawValue, forKey: "dataMode")
    }
  }

  init() {
    // Initialize storedModeRaw from UserDefaults
    self.storedModeRaw = UserDefaults.standard.string(forKey: "dataMode") ?? DataMode.live.rawValue
    // Seed mode from stored raw value
    self.mode = DataMode(rawValue: storedModeRaw) ?? .live
  }
}
