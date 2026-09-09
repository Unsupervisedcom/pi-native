import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PiNative

@MainActor
final class ArchivedChatsRenderingTests: XCTestCase {
    func testEmptyStateRenders() throws {
        let model = AppModel()
        model.projects = []
        model.standaloneSessions = []
        model.openRightPane(.archivedChats)

        // 2119: REQ-013.1.2
        let hostingView = NSHostingView(rootView: RightPaneView().environmentObject(model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 640)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: image).perform([request])
        let renderedText = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")

        XCTAssertTrue(renderedText.contains("No Archived Chats"), "Rendered text: \(renderedText)")
    }
}
