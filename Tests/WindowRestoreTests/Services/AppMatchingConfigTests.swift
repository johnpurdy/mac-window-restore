import Testing
import Foundation
@testable import WindowRestore

@Suite("AppMatchingConfig Tests")
struct AppMatchingConfigTests {

    @Test("Decodes from valid JSON")
    func decodesFromValidJSON() throws {
        let json = """
        {
            "multiWindowApps": ["com.apple.finder", "com.google.Chrome"],
            "tabEnabledApps": ["com.google.Chrome"],
            "tabMatchThreshold": 0.5
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppMatchingConfig.self, from: data)

        #expect(config.multiWindowApps == ["com.apple.finder", "com.google.Chrome"])
        #expect(config.tabEnabledApps == ["com.google.Chrome"])
        #expect(config.tabMatchThreshold == 0.5)
    }

    @Test("isMultiWindowApp returns true for listed apps")
    func isMultiWindowAppReturnsTrue() throws {
        let json = """
        {
            "multiWindowApps": ["com.apple.finder"],
            "tabEnabledApps": [],
            "tabMatchThreshold": 0.5
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppMatchingConfig.self, from: data)

        #expect(config.isMultiWindowApp("com.apple.finder") == true)
    }

    @Test("isMultiWindowApp returns false for unlisted apps")
    func isMultiWindowAppReturnsFalse() throws {
        let json = """
        {
            "multiWindowApps": ["com.apple.finder"],
            "tabEnabledApps": [],
            "tabMatchThreshold": 0.5
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppMatchingConfig.self, from: data)

        #expect(config.isMultiWindowApp("com.apple.calculator") == false)
    }

    @Test("isTabEnabledApp returns true for listed apps")
    func isTabEnabledAppReturnsTrue() throws {
        let json = """
        {
            "multiWindowApps": ["com.google.Chrome"],
            "tabEnabledApps": ["com.google.Chrome"],
            "tabMatchThreshold": 0.5
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppMatchingConfig.self, from: data)

        #expect(config.isTabEnabledApp("com.google.Chrome") == true)
    }

    @Test("isTabEnabledApp returns false for unlisted apps")
    func isTabEnabledAppReturnsFalse() throws {
        let json = """
        {
            "multiWindowApps": ["com.google.Chrome"],
            "tabEnabledApps": ["com.google.Chrome"],
            "tabMatchThreshold": 0.5
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppMatchingConfig.self, from: data)

        #expect(config.isTabEnabledApp("com.apple.finder") == false)
    }

    @Test("Provides sensible defaults when loading fails")
    func providesSensibleDefaults() {
        let config = AppMatchingConfig.loadOrDefault(from: URL(fileURLWithPath: "/nonexistent/path.json"))

        #expect(config.multiWindowApps.contains("com.google.Chrome"))
        #expect(config.multiWindowApps.contains("com.apple.finder"))
        #expect(config.tabEnabledApps.contains("com.google.Chrome"))
        #expect(config.tabMatchThreshold == 0.5)
    }
}
