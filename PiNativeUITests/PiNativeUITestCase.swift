import AppKit
import XCTest

@MainActor
class PiNativeUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func clickNewChat(in app: XCUIApplication) {
        let newChatButton = app.buttons["sidebar.newChatButton"]
        XCTAssertTrue(newChatButton.waitForExistence(timeout: 10))
        newChatButton.click()
    }

    static func writePersistedAppDefault(key: String, value: String, file: StaticString = #filePath, line: UInt = #line) {
        runDefaultsCommand(arguments: ["write", "com.unsupervised.PiNative", key, value], file: file, line: line)
    }

    static func deletePersistedAppDefault(key: String, file: StaticString = #filePath, line: UInt = #line) {
        runDefaultsCommand(arguments: ["delete", "com.unsupervised.PiNative", key], file: file, line: line)
    }

    static func runDefaultsCommand(arguments: [String], file: StaticString = #filePath, line: UInt = #line) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            XCTFail("Failed to run defaults \(arguments.joined(separator: " ")): \(error)", file: file, line: line)
            return
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            XCTFail("defaults \(arguments.joined(separator: " ")) exited with status \(process.terminationStatus)", file: file, line: line)
            return
        }
    }

    func assertElementContainsVisibleRed(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        assertElementPixels(element, description: "visible red pixels", file: file, line: line) { color in
            color.alphaComponent > 0.25
                && color.redComponent > 0.35
                && color.redComponent > color.greenComponent + 0.10
                && color.redComponent > color.blueComponent + 0.10
        }
    }

    func assertElementContainsVisibleNonNeutralPixels(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        assertElementPixels(element, description: "visible non-neutral pixels", file: file, line: line) { color in
            let maxChannel = max(color.redComponent, color.greenComponent, color.blueComponent)
            let minChannel = min(color.redComponent, color.greenComponent, color.blueComponent)
            return color.alphaComponent > 0.25 && maxChannel - minChannel > 0.08
        }
    }

    func assertElementFullyInsideWindow(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let windowFrame = app.windows.firstMatch.frame
        let frame = element.frame
        XCTAssertGreaterThan(frame.width, 20, file: file, line: line)
        XCTAssertGreaterThan(frame.height, 10, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, windowFrame.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, windowFrame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, windowFrame.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, windowFrame.maxY, file: file, line: line)
    }

    func assertElementDoesNotOverlap(_ element: XCUIElement, _ blocker: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        guard element.exists, blocker.exists, !element.frame.isEmpty, !blocker.frame.isEmpty else { return }
        XCTAssertFalse(
            element.frame.intersects(blocker.frame),
            "Expected \(element) not to overlap visible shell/sidebar region \(blocker)",
            file: file,
            line: line
        )
    }

    func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return !element.exists
    }

    func recursiveUTF8FileContents(in root: URL) throws -> [String: String] {
        let root = root.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var contents: [String: String] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            contents[String(path.dropFirst(prefix.count))] = try String(contentsOf: url)
        }
        return contents
    }

    func assertElementPixels(
        _ element: XCUIElement,
        description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        predicate: (NSColor) -> Bool
    ) {
        guard let bitmap = NSBitmapImageRep(data: element.screenshot().pngRepresentation) else {
            return XCTFail("Could not decode element screenshot", file: file, line: line)
        }

        var matchingPixelCount = 0
        let step = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 80)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if predicate(color) { matchingPixelCount += 1 }
            }
        }

        XCTAssertGreaterThan(matchingPixelCount, 0, "Expected element screenshot to contain \(description)", file: file, line: line)
    }

}
