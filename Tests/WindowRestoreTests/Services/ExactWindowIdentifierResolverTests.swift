import Testing
import Foundation
import ApplicationServices
@testable import WindowRestore

@Suite("ExactWindowIdentifierResolver Tests")
struct ExactWindowIdentifierResolverTests {

    /// A throwaway AX element; the injected backend ignores it, so its identity
    /// does not matter here — only that it is a valid AXUIElement to pass.
    private func dummyElement() -> AXUIElement {
        AXUIElementCreateApplication(getpid())
    }

    @Test("Maps a successful backend result to its exact CGWindowID")
    func successMapsToId() {
        let resolver = ExactWindowIdentifierResolver(backend: { _ in
            (.success, CGWindowID(4242))
        })

        #expect(resolver.windowIdentifier(for: dummyElement()) == 4242)
    }

    @Test("Maps any non-success backend result to nil (fail-closed)")
    func failureMapsToNil() {
        let resolver = ExactWindowIdentifierResolver(backend: { _ in
            (.failure, CGWindowID(0))
        })

        #expect(resolver.windowIdentifier(for: dummyElement()) == nil)
    }

    @Test("Does not fabricate an id when the element cannot be resolved")
    func invalidValueMapsToNil() {
        // Even if the backend hands back a nonzero id, a non-success error must
        // still yield nil — the id is only trustworthy on .success.
        let resolver = ExactWindowIdentifierResolver(backend: { _ in
            (.invalidUIElement, CGWindowID(99999))
        })

        #expect(resolver.windowIdentifier(for: dummyElement()) == nil)
    }
}
