import Foundation

/// Neutralizes duplicate window identifiers from a single enumeration pass.
///
/// The exact-CGWindowID resolver should return a unique id per window. If it ever
/// returns the same non-nil id for two or more windows, that is a malfunction, not a
/// valid state: trusting it would let `WindowMatcher` / `WindowMerger` make an arbitrary
/// confident match. So every window sharing a duplicated id is mapped to `nil`, forcing a
/// safe fallback to tab/title matching. Pure and order-preserving so it is unit-testable
/// without live Accessibility calls.
public enum WindowIdentifierNormalization {

    /// Maps an ordered list of identifiers to the same list with any non-nil identifier
    /// that appears more than once set to `nil`. Order is preserved; existing `nil`s stay
    /// `nil`; identifiers that appear exactly once are untouched.
    public static func normalizedIdentifiers(_ identifiers: [Int?]) -> [Int?] {
        var counts: [Int: Int] = [:]
        for case let identifier? in identifiers {
            counts[identifier, default: 0] += 1
        }
        return identifiers.map { identifier in
            guard let identifier else { return nil }
            return counts[identifier] == 1 ? identifier : nil
        }
    }

    /// Non-nil identifiers that appear more than once, sorted (for logging).
    public static func duplicateIdentifiers(_ identifiers: [Int?]) -> [Int] {
        var counts: [Int: Int] = [:]
        for case let identifier? in identifiers {
            counts[identifier, default: 0] += 1
        }
        return counts.filter { $0.value > 1 }.keys.sorted()
    }

    /// Value-preserving normalization for raw windows: duplicated non-nil identifiers are
    /// mapped to `nil` while every other field and the order are left unchanged.
    public static func normalizeDuplicates(_ raws: [RawWindow]) -> [RawWindow] {
        let normalized = normalizedIdentifiers(raws.map { $0.windowIdentifier })
        return zip(raws, normalized).map { $0.withWindowIdentifier($1) }
    }

    /// Value-preserving normalization for restore records: duplicated non-nil identifiers
    /// are mapped to `nil` while the bound AX element, every other field, and the order are
    /// left unchanged.
    public static func normalizeDuplicates(_ records: [CurrentWindowRecord]) -> [CurrentWindowRecord] {
        let normalized = normalizedIdentifiers(records.map { $0.currentWindow.windowIdentifier })
        return zip(records, normalized).map { record, identifier in
            CurrentWindowRecord(
                element: record.element,
                currentWindow: record.currentWindow.withWindowIdentifier(identifier)
            )
        }
    }
}
