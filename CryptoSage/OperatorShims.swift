// Shim to safely use the identity-like operator with value types in this codebase.
// In Swift, `!==` is defined for object identity. We provide an overload for optional Double
// that simply defers to value inequality, so existing code that accidentally uses `!==`
// with `Double?` will compile and behave as intended (detecting changes).

import Foundation

@inlinable func !== (lhs: Double?, rhs: Double?) -> Bool {
    return lhs != rhs
}
