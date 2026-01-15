import Foundation
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

public struct PlistDiagnostics {
    
    /// Masks sensitive string values by showing first 3 characters and length.
    /// If string length is less than 3, shows the entire string.
    /// Example: "ABC••• len=32"
    private static func mask(_ value: String) -> String {
        let count = value.count
        guard count >= 3 else {
            return "\(value)••• len=\(count)"
        }
        let prefix = value.prefix(3)
        return "\(prefix)••• len=\(count)"
    }
    
    public static func audit() {
        print("[PlistAudit] --- Runtime Info.plist audit ---")
        
        guard let infoDict = Bundle.main.infoDictionary else {
            print("[PlistAudit] Unable to read Bundle.main.infoDictionary")
            print("[PlistAudit] --- End audit ---")
            return
        }
        
        if let bundleID = infoDict["CFBundleIdentifier"] as? String {
            print("[PlistAudit] CFBundleIdentifier = \(bundleID)")
        } else {
            print("[PlistAudit] CFBundleIdentifier = <missing>")
        }
        
        if let bundleName = infoDict["CFBundleName"] as? String {
            print("[PlistAudit] CFBundleName = \(bundleName)")
        } else {
            print("[PlistAudit] CFBundleName = <missing>")
        }
        
        if let bundleVersion = infoDict["CFBundleVersion"] as? String {
            print("[PlistAudit] CFBundleVersion = \(bundleVersion)")
        } else {
            print("[PlistAudit] CFBundleVersion = <missing>")
        }
        
        if let shortVersion = infoDict["CFBundleShortVersionString"] as? String {
            print("[PlistAudit] CFBundleShortVersionString = \(shortVersion)")
        } else {
            print("[PlistAudit] CFBundleShortVersionString = <missing>")
        }
        
        if let infoPlistPath = Bundle.main.path(forResource: "Info", ofType: "plist") {
            print("[PlistAudit] Info.plist path: \(infoPlistPath)")
        } else {
            print("[PlistAudit] Info.plist path: <not found>")
        }
        
        if let atsDict = infoDict["NSAppTransportSecurity"] as? [String: Any] {
            print("[PlistAudit] NSAppTransportSecurity is present")
            if let allowsArbitraryLoads = atsDict["NSAllowsArbitraryLoads"] as? Bool {
                print("[PlistAudit] NSAllowsArbitraryLoads = \(allowsArbitraryLoads)")
            } else {
                print("[PlistAudit] NSAllowsArbitraryLoads = <not set>")
            }
        } else {
            print("[PlistAudit] NSAppTransportSecurity is NOT present")
        }
        
        var sidecarURL: URL? = nil
        if let url = Bundle.main.url(forResource: "CryptoSageConfig", withExtension: "plist") {
            sidecarURL = url
            print("[PlistAudit] Sidecar CryptoSageConfig.plist found at: \(url.path)")
        } else {
            print("[PlistAudit] Sidecar CryptoSageConfig.plist NOT found")
        }
        
        var sidecarDict: [String: Any]? = nil
        if let sidecarURL = sidecarURL {
            do {
                let data = try Data(contentsOf: sidecarURL)
                let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                sidecarDict = plist as? [String: Any]
            } catch {
                print("[PlistAudit] Failed to load sidecar plist: \(error)")
            }
        }
        
        let keys = [
            "3COMMAS_READ_ONLY_KEY",
            "3COMMAS_READ_ONLY_SECRET",
            "3COMMAS_TRADING_API_KEY",
            "3COMMAS_TRADING_SECRET",
            "3COMMAS_ACCOUNT_ID"
        ]
        
        for key in keys {
            var source = "Missing"
            var valuePreview = "<missing>"
            
            // Check Info.plist first
            if let infoValue = Bundle.main.object(forInfoDictionaryKey: key) as? String, !infoValue.isEmpty {
                source = "Info"
                valuePreview = mask(infoValue)
            }
            // Check sidecar plist if not found in Info.plist
            else if let sidecarDict = sidecarDict,
                    let sidecarValue = sidecarDict[key] as? String,
                    !sidecarValue.isEmpty {
                source = "Sidecar"
                valuePreview = mask(sidecarValue)
            }
            
            print("[PlistAudit] KEY=\(key) source=\(source) valuePreview=\(valuePreview)")
        }
        
        print("[PlistAudit] --- End audit ---")
    }
}

#if DEBUG
extension PlistDiagnostics {
    private static var didRunOnce = false
    
    /// Runs the audit only once per process.
    public static func runOnLaunchOnce() {
        guard !didRunOnce else { return }
        didRunOnce = true
        audit()
    }
}
#endif
