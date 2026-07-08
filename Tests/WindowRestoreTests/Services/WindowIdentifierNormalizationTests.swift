import Testing
import CoreGraphics
import ApplicationServices
@testable import WindowRestore

@Suite("WindowIdentifierNormalization Tests")
struct WindowIdentifierNormalizationTests {

    @Test("No duplicates pass through unchanged")
    func noDuplicatesUnchanged() {
        #expect(WindowIdentifierNormalization.normalizedIdentifiers([1, 2, 3]) == [1, 2, 3])
    }

    @Test("Duplicate non-nil ids all become nil")
    func duplicatesBecomeNil() {
        #expect(WindowIdentifierNormalization.normalizedIdentifiers([7, 7, 3]) == [nil, nil, 3])
    }

    @Test("Existing nil stays nil and order is preserved")
    func nilStaysNilOrderPreserved() {
        #expect(WindowIdentifierNormalization.normalizedIdentifiers([nil, 5, nil, 5, 9]) == [nil, nil, nil, nil, 9])
    }

    @Test("Reports duplicated identifiers for logging")
    func reportsDuplicates() {
        #expect(WindowIdentifierNormalization.duplicateIdentifiers([7, 7, 3, 9, 9]) == [7, 9])
        #expect(WindowIdentifierNormalization.duplicateIdentifiers([1, 2, 3]).isEmpty)
    }

    @Test("RawWindow normalization neutralizes duplicate ids while preserving fields and order")
    func rawWindowNormalizationPreservesFieldsAndOrder() {
        func raw(_ title: String, _ id: Int?) -> RawWindow {
            RawWindow(
                bundleIdentifier: "com.microsoft.edgemac",
                applicationName: "Microsoft Edge",
                title: title,
                frame: CGRect(x: 1, y: 2, width: 3, height: 4),
                isMinimized: false,
                windowIdentifier: id,
                tabs: [title]
            )
        }
        let input = [raw("A", 7), raw("B", 7), raw("C", 3), raw("D", nil)]

        let result = WindowIdentifierNormalization.normalizeDuplicates(input)

        // Duplicated id 7 neutralized; unique id 3 and existing nil untouched.
        #expect(result.map { $0.windowIdentifier } == [nil, nil, 3, nil])
        // Order and all other fields preserved.
        #expect(result.map { $0.title } == ["A", "B", "C", "D"])
        #expect(result.map { $0.tabs } == [["A"], ["B"], ["C"], ["D"]])
        #expect(result.allSatisfy { $0.frame == CGRect(x: 1, y: 2, width: 3, height: 4) })
    }

    @Test("Restore-record normalization neutralizes duplicate ids while preserving elements and order")
    func currentRecordNormalizationPreservesElementsAndOrder() {
        func record(_ title: String, _ id: Int?, _ pid: pid_t) -> CurrentWindowRecord {
            CurrentWindowRecord(
                element: AXUIElementCreateApplication(pid),
                currentWindow: CurrentWindow(
                    bundleIdentifier: "com.microsoft.edgemac",
                    title: title,
                    frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                    windowIdentifier: id,
                    tabs: nil
                )
            )
        }
        let input = [record("A", 7, 701), record("B", 7, 702), record("C", 3, 703)]

        let result = WindowIdentifierNormalization.normalizeDuplicates(input)

        #expect(result.map { $0.currentWindow.windowIdentifier } == [nil, nil, 3])
        #expect(result.map { $0.currentWindow.title } == ["A", "B", "C"])
        // The bound AX element (by identity) and order are preserved.
        #expect(CFEqual(result[0].element, input[0].element))
        #expect(CFEqual(result[1].element, input[1].element))
        #expect(CFEqual(result[2].element, input[2].element))
    }
}
