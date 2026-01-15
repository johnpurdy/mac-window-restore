import Testing
import Foundation
@testable import WindowRestore

@Suite("TabEnumerator Tests")
struct TabEnumeratorTests {

    @Test("supportsTabEnumeration returns true for tab-enabled apps")
    func supportsTabEnumerationReturnsTrue() {
        // This uses the default config which includes Chrome
        #expect(TabEnumerator.supportsTabEnumeration(bundleIdentifier: "com.google.Chrome") == true)
        #expect(TabEnumerator.supportsTabEnumeration(bundleIdentifier: "com.microsoft.edgemac") == true)
    }

    @Test("supportsTabEnumeration returns false for non-tab apps")
    func supportsTabEnumerationReturnsFalse() {
        #expect(TabEnumerator.supportsTabEnumeration(bundleIdentifier: "com.apple.finder") == false)
        #expect(TabEnumerator.supportsTabEnumeration(bundleIdentifier: "com.apple.calculator") == false)
    }

    @Test("TabEnumerator can be instantiated")
    func canBeInstantiated() {
        let enumerator = TabEnumerator()
        #expect(enumerator != nil)
    }
}
