import AppKit
import XCTest
@testable import PiNative

final class AttachmentSupportTests: XCTestCase {
    // 2119: REQ-001.3.2
    // 2119: REQ-001.4.5
    func testFileReferenceAttachmentsBecomePathReferencesWithoutInliningContents() throws {
        let pdfURL = temporaryURL(extension: "pdf")
        let textURL = temporaryURL(extension: "txt")
        let pdfSentinel = "PDF sentinel contents that must not be inlined"
        let textSentinel = "Text sentinel contents that must not be inlined"
        try pdfSentinel.write(to: pdfURL, atomically: true, encoding: .utf8)
        try textSentinel.write(to: textURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: pdfURL)
            try? FileManager.default.removeItem(at: textURL)
        }

        let attachments = [pdfURL, textURL].map { url in
            ComposerAttachment(kind: .fileReference(FileReferenceAttachment(
                url: url,
                displayName: url.lastPathComponent,
                fileSize: 123
            )))
        }

        let prepared = try XCTUnwrap(PromptAttachmentAssembler.prepare(
            draft: "Please review these files.",
            attachments: attachments
        ))

        let expectedMessage = """
        Attached files:
        - \(pdfURL.path)
        - \(textURL.path)

        User message:
        Please review these files.
        """
        XCTAssertEqual(prepared.message, expectedMessage)
        XCTAssertFalse(prepared.message.contains(pdfSentinel))
        XCTAssertFalse(prepared.message.contains(textSentinel))
        XCTAssertFalse(prepared.message.contains(Data(pdfSentinel.utf8).base64EncodedString()))
        XCTAssertFalse(prepared.message.contains(Data(textSentinel.utf8).base64EncodedString()))
        XCTAssertTrue(prepared.images.isEmpty)

        let rpcFields = PiRPCClient.promptFields(message: prepared.message, images: prepared.images)
        XCTAssertEqual(rpcFields["message"]?.stringValue, prepared.message)
        XCTAssertNil(rpcFields["images"])
    }

    // 2119: REQ-001.3.1
    func testImageAttachmentsBecomeRPCImagesWithoutAttachedFilesBlock() throws {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let attachments = [
            ComposerAttachment(kind: .image(ImageAttachment(
                data: pngData,
                mimeType: "image/png",
                displayName: "sample.png",
                sourceURL: nil,
                pixelWidth: 1,
                pixelHeight: 1
            ))),
            ComposerAttachment(kind: .image(ImageAttachment(
                data: jpegData,
                mimeType: "image/jpeg",
                displayName: "sample.jpg",
                sourceURL: nil,
                pixelWidth: 1,
                pixelHeight: 1
            )))
        ]

        let prepared = try XCTUnwrap(PromptAttachmentAssembler.prepare(
            draft: "What is in these images?",
            attachments: attachments
        ))

        XCTAssertEqual(prepared.message, "What is in these images?")
        XCTAssertFalse(prepared.message.contains("Attached files:"))
        XCTAssertEqual(prepared.images.count, 2)
        XCTAssertEqual(prepared.images[0].type, "image")
        XCTAssertEqual(prepared.images[0].mimeType, "image/png")
        XCTAssertEqual(prepared.images[0].data, pngData.base64EncodedString())
        XCTAssertEqual(prepared.images[1].type, "image")
        XCTAssertEqual(prepared.images[1].mimeType, "image/jpeg")
        XCTAssertEqual(prepared.images[1].data, jpegData.base64EncodedString())
    }

    // 2119: REQ-001.3.2
    // 2119: REQ-001.3.3
    func testAttachmentOnlyDraftProducesNonemptyPrompt() throws {
        let fileAttachment = ComposerAttachment(kind: .fileReference(FileReferenceAttachment(
            url: URL(fileURLWithPath: "/tmp/only-file.pdf"),
            displayName: "only-file.pdf",
            fileSize: nil
        )))
        let imageAttachment = ComposerAttachment(kind: .image(ImageAttachment(
            data: Data([1, 2, 3]),
            mimeType: "image/png",
            displayName: "only-image.png",
            sourceURL: nil,
            pixelWidth: 1,
            pixelHeight: 1
        )))

        let fileOnly = try XCTUnwrap(PromptAttachmentAssembler.prepare(draft: "", attachments: [fileAttachment]))
        let fileOnlyWhitespace = try XCTUnwrap(PromptAttachmentAssembler.prepare(draft: "   \n", attachments: [fileAttachment]))
        let imageOnly = try XCTUnwrap(PromptAttachmentAssembler.prepare(draft: "", attachments: [imageAttachment]))
        let imageOnlyWhitespace = try XCTUnwrap(PromptAttachmentAssembler.prepare(draft: "   \n", attachments: [imageAttachment]))
        let mixedWhitespace = try XCTUnwrap(PromptAttachmentAssembler.prepare(draft: "   \n", attachments: [fileAttachment, imageAttachment]))

        let expectedFileOnlyMessage = """
        Attached files:
        - /tmp/only-file.pdf

        Please consider the attached file references.
        """
        XCTAssertEqual(fileOnly.message, expectedFileOnlyMessage)
        XCTAssertEqual(fileOnlyWhitespace.message, expectedFileOnlyMessage)
        XCTAssertFalse(fileOnly.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(imageOnly.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(imageOnly.images.count, 1)
        XCTAssertFalse(imageOnlyWhitespace.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(imageOnlyWhitespace.images.count, 1)
        XCTAssertEqual(mixedWhitespace.message, expectedFileOnlyMessage)
        XCTAssertEqual(mixedWhitespace.images.count, 1)
    }

    // 2119: REQ-001.3.4
    func testEmptyDraftAndEmptyAttachmentsDoesNotPreparePrompt() {
        XCTAssertNil(PromptAttachmentAssembler.prepare(draft: "", attachments: []))
        XCTAssertNil(PromptAttachmentAssembler.prepare(draft: "   \n", attachments: []))
    }

    // 2119: REQ-001.4.1
    func testPasteboardBitmapImageBecomesImageAttachment() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PiNativeAttachmentSupportTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([try makeImage()]))

        let result = AttachmentClassifier.attachments(from: pasteboard)

        XCTAssertTrue(result.didHandle)
        XCTAssertTrue(result.errors.isEmpty)
        let attachment = try XCTUnwrap(result.attachments.first)
        guard case .image(let image) = attachment.kind else {
            return XCTFail("Expected image attachment")
        }
        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertFalse(image.data.isEmpty)
        XCTAssertEqual(image.displayName, "Pasted image")
    }

    // 2119: REQ-001.4.2
    func testImageFileURLBecomesImageAttachment() throws {
        let pngURL = temporaryURL(extension: "png")
        let jpgURL = temporaryURL(extension: "jpg")
        let jpegURL = temporaryURL(extension: "jpeg")
        try makeImage().pngDataForTests.write(to: pngURL)
        try makeImage().jpegDataForTests.write(to: jpgURL)
        try makeImage().jpegDataForTests.write(to: jpegURL)
        defer {
            try? FileManager.default.removeItem(at: pngURL)
            try? FileManager.default.removeItem(at: jpgURL)
            try? FileManager.default.removeItem(at: jpegURL)
        }

        let result = AttachmentClassifier.attachments(from: [pngURL, jpgURL, jpegURL])

        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.attachments.count, 3)
        guard case .image(let pngImage) = result.attachments[0].kind else {
            return XCTFail("Expected PNG image attachment")
        }
        guard case .image(let jpgImage) = result.attachments[1].kind else {
            return XCTFail("Expected JPG image attachment")
        }
        guard case .image(let jpegImage) = result.attachments[2].kind else {
            return XCTFail("Expected JPEG image attachment")
        }
        XCTAssertEqual(pngImage.mimeType, "image/png")
        XCTAssertEqual(pngImage.sourceURL?.path, pngURL.standardizedFileURL.path)
        XCTAssertEqual(pngImage.displayName, pngURL.lastPathComponent)
        XCTAssertFalse(pngImage.data.isEmpty)
        XCTAssertEqual(jpgImage.mimeType, "image/jpeg")
        XCTAssertEqual(jpgImage.sourceURL?.path, jpgURL.standardizedFileURL.path)
        XCTAssertEqual(jpgImage.displayName, jpgURL.lastPathComponent)
        XCTAssertFalse(jpgImage.data.isEmpty)
        XCTAssertEqual(jpegImage.mimeType, "image/jpeg")
        XCTAssertEqual(jpegImage.sourceURL?.path, jpegURL.standardizedFileURL.path)
        XCTAssertEqual(jpegImage.displayName, jpegURL.lastPathComponent)
        XCTAssertFalse(jpegImage.data.isEmpty)
    }

    // 2119: REQ-001.4.3
    func testNonImageRegularFileURLsBecomeFileReferenceAttachments() throws {
        let pdfURL = temporaryURL(extension: "pdf")
        let uppercasePDFURL = temporaryURL(extension: "PDF")
        let textURL = temporaryURL(extension: "txt")
        let binaryURL = temporaryURL(extension: "bin")
        let extensionlessURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinative-attachment-test-\(UUID().uuidString)")
        try "%PDF-1.4 test fixture".write(to: pdfURL, atomically: true, encoding: .utf8)
        try "%PDF-1.4 uppercase test fixture".write(to: uppercasePDFURL, atomically: true, encoding: .utf8)
        try "plain text fixture".write(to: textURL, atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02, 0xFE, 0xFF]).write(to: binaryURL)
        try "extensionless fixture".write(to: extensionlessURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: pdfURL)
            try? FileManager.default.removeItem(at: uppercasePDFURL)
            try? FileManager.default.removeItem(at: textURL)
            try? FileManager.default.removeItem(at: binaryURL)
            try? FileManager.default.removeItem(at: extensionlessURL)
        }

        let urls = [pdfURL, uppercasePDFURL, textURL, binaryURL, extensionlessURL]
        let result = AttachmentClassifier.attachments(from: urls)

        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.attachments.count, urls.count)
        for (attachment, url) in zip(result.attachments, urls) {
            guard case .fileReference(let file) = attachment.kind else {
                return XCTFail("Expected file-reference attachment for \(url.lastPathComponent)")
            }
            XCTAssertEqual(file.url.path, url.standardizedFileURL.path)
            XCTAssertEqual(file.displayName, url.lastPathComponent)
        }
    }

    // 2119: REQ-001.4.4
    func testMissingFileReportsAttachmentError() throws {
        let missingURL = temporaryURL(extension: "missing")

        let result = AttachmentClassifier.attachments(from: [missingURL])

        XCTAssertTrue(result.attachments.isEmpty)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertNotNil(result.errors.first?.localizedDescription)
    }

    func testRPCPromptFieldsOmitImagesForTextOnlyPrompts() {
        let fields = PiRPCClient.promptFields(message: "Hello")

        XCTAssertEqual(fields["message"]?.stringValue, "Hello")
        XCTAssertNil(fields["images"])
    }

    // 2119: REQ-001.3.1
    func testRPCPromptFieldsEncodeImagesWhenPresent() throws {
        let image = RPCImageContent(mimeType: "image/png", data: "abc123")

        let fields = PiRPCClient.promptFields(message: "Look", images: [image])

        XCTAssertEqual(fields["message"]?.stringValue, "Look")
        let images = try XCTUnwrap(fields["images"]?.arrayValue)
        XCTAssertEqual(images.count, 1)
        let object = try XCTUnwrap(images[0].objectValue)
        XCTAssertEqual(object["type"]?.stringValue, "image")
        XCTAssertEqual(object["mimeType"]?.stringValue, "image/png")
        XCTAssertEqual(object["data"]?.stringValue, "abc123")
    }

    private func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pinative-attachment-test-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    private func makeImage() throws -> NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        image.unlockFocus()
        return image
    }
}

private extension NSImage {
    var pngDataForTests: Data {
        get throws {
            guard let data = pngData else { throw XCTSkip("Could not create PNG data") }
            return data
        }
    }

    var jpegDataForTests: Data {
        get throws {
            guard
                let tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffRepresentation),
                let data = bitmap.representation(using: .jpeg, properties: [:])
            else { throw XCTSkip("Could not create JPEG data") }
            return data
        }
    }
}

@MainActor
final class AppModelProjectFolderDefaultsTests: XCTestCase {
    private let defaultsKey = "promote.defaultCodeFolder"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        super.tearDown()
    }

    // 2119: REQ-002.1.4
    func testMissingPersistedProjectFolderDefaultsToProjectsPath() {
        let model = AppModel()

        XCTAssertEqual(model.promoteDefaultCodeFolder, "~/Projects")
    }

    // 2119: REQ-002.1.4
    func testProjectFolderCreationCreatesMissingDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeProjectFolderDefault-\(UUID().uuidString)", isDirectory: true)
        let projectFolder = root.appendingPathComponent("Projects", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        AppModel.ensureProjectFolderExists(at: projectFolder.path)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectFolder.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}

final class PromoteToProjectAlwaysOnArtifactsTests: XCTestCase {
    // 2119: REQ-002.2.2
    func testPromotedChatProvenanceIsAlwaysCreated() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativePromoteAlwaysOn-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sessionID = UUID()
        let session = Session(
            id: sessionID,
            name: "Source Planning Chat",
            status: .idle,
            cachedTranscript: [.user(id: UUID(), UserMessagePayload(text: "Build the thing"))]
        )
        let request = PromoteToProjectRequest(
            sourceSession: session,
            projectName: "Always On Artifacts",
            codeFolder: root.path,
            options: PromoteToProjectOptions(seedProjectMemory: false, addAgentInstructions: false)
        )
        let service = PromoteToProjectService(fileManager: .default, now: { Date(timeIntervalSince1970: 1) })

        let destination = try service.validate(request)
        try service.prepareDestination(destination, sourceSession: session)
        _ = try service.createArtifacts(request: request, destination: destination)

        let provenanceURL = destination.destinationURL.appendingPathComponent("promoted-chat.md")
        let provenance = try String(contentsOf: provenanceURL)
        XCTAssertTrue(provenance.contains("Source Planning Chat"))
        XCTAssertTrue(provenance.contains(sessionID.uuidString))
        let timestampLine = try XCTUnwrap(provenance.split(separator: "\n").first { $0.contains("Promotion timestamp:") })
        XCTAssertEqual(timestampLine, "- Promotion timestamp: 1970-01-01T00:00:01Z")
        XCTAssertNotNil(ISO8601DateFormatter().date(from: String(timestampLine).replacingOccurrences(of: "- Promotion timestamp: ", with: "")))
        XCTAssertTrue(provenance.contains("Cached transcript included"))
        XCTAssertTrue(provenance.contains("Build the thing"))
    }
}
