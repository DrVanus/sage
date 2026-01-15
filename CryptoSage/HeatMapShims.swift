import SwiftUI

// Lightweight global shims to bridge older call sites that used unqualified helpers.
// These forward to the canonical implementations in HeatMapSharedLib.
// This avoids touching many files and resolves "Cannot find X in scope" errors.

@inline(__always)
func change(for tile: HeatMapTile, tf: HeatMapTimeframe) -> Double {
    HeatMapSharedLib.change(for: tile, tf: tf)
}

@inline(__always)
func bound(for tf: HeatMapTimeframe) -> Double {
    HeatMapSharedLib.bound(for: tf)
}

@inline(__always)
func valueAbbrev(_ v: Double) -> String {
    HeatMapSharedLib.valueAbbrev(v)
}

@inline(__always)
func percentStringAdaptive(_ v: Double) -> String {
    HeatMapSharedLib.percentStringAdaptive(v)
}
