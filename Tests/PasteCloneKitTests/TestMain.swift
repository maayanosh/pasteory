import Foundation

// Minimal self-contained test harness.
//
// This machine's CommandLineTools cannot run SwiftPM (mismatched
// PackageDescription module/dylib), ships no XCTest, and its Testing.framework
// swiftinterface fails to compile against the installed SDK (swiftlang 6.2.3
// SDK vs 6.2.4 compiler). So tests are compiled together with the app sources
// into this plain executable; exit code 0 = all green.

@MainActor var testFailures = 0
@MainActor var testsRun = 0
@MainActor private var currentTestName = ""

@MainActor
func expect(_ condition: Bool, _ message: String = "",
            file: StaticString = #filePath, line: Int = #line) {
    if !condition {
        testFailures += 1
        print("    ✘ expectation failed\(message.isEmpty ? "" : ": \(message)") (\(file):\(line))")
    }
}

@MainActor
func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "",
                               file: StaticString = #filePath, line: Int = #line) {
    if a != b {
        testFailures += 1
        print("    ✘ \(String(describing: a)) != \(String(describing: b))"
              + "\(message.isEmpty ? "" : " — \(message)") (\(file):\(line))")
    }
}

@MainActor
func test(_ name: String, _ body: @MainActor () throws -> Void) {
    testsRun += 1
    currentTestName = name
    let before = testFailures
    do {
        try body()
    } catch {
        testFailures += 1
        print("  ✘ \(name) threw: \(error)")
        return
    }
    print(testFailures == before ? "  ✔ \(name)" : "  ✘ \(name)")
}

@main
struct TestRunner {
    @MainActor
    static func main() {
        print("PasteClone test suite\n")
        print("ModelsTests");    modelsTests()
        print("SHA256Tests");    sha256Tests()
        print("AppColorsTests"); appColorsTests()
        print("StoreTests");     storeTests()
        print("FilterTests");    filterTests()
        print("")
        if testFailures == 0 {
            print("ALL \(testsRun) TESTS PASSED")
            exit(0)
        } else {
            print("\(testFailures) FAILURE(S) across \(testsRun) tests")
            exit(1)
        }
    }
}
