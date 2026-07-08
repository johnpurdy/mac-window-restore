import Testing
import ApplicationServices
@testable import WindowRestore

@Suite("WindowIdentifierResolver Tests")
struct WindowIdentifierResolverTests {

    @Test("Success returns the identifier as Int")
    func successReturnsIdentifier() {
        #expect(AXWindowIdentifierResolver.resolve(error: .success, windowId: 12345) == 12345)
    }

    @Test("Non-success returns nil")
    func nonSuccessReturnsNil() {
        #expect(AXWindowIdentifierResolver.resolve(error: .failure, windowId: 12345) == nil)
        #expect(AXWindowIdentifierResolver.resolve(error: .invalidUIElement, windowId: 999) == nil)
    }

    @Test("Success with null window id returns nil")
    func successWithNullWindowIdReturnsNil() {
        #expect(AXWindowIdentifierResolver.resolve(error: .success, windowId: 0) == nil)
    }
}
