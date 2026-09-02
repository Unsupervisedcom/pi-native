import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RPCImageContent: Hashable, Codable, Sendable {
    var type: String = "image"
    var mimeType: String
    var data: String
}

struct ImageAttachment: Hashable, Codable {
    var data: Data
    var mimeType: String
    var displayName: String?
    var sourceURL: URL?
    var pixelWidth: Double?
    var pixelHeight: Double?

    var nsImage: NSImage? { NSImage(data: data) }
}

struct FileReferenceAttachment: Hashable, Codable {
    var url: URL
    var displayName: String
    var fileSize: Int64?
}

struct ComposerAttachment: Identifiable, Hashable, Codable {
    enum Kind: Hashable, Codable {
        case image(ImageAttachment)
        case fileReference(FileReferenceAttachment)
    }

    var id: UUID = UUID()
    var kind: Kind

    var displayName: String {
        switch kind {
        case .image(let image): image.displayName ?? image.sourceURL?.lastPathComponent ?? "Image"
        case .fileReference(let file): file.displayName
        }
    }
}

struct PreparedPrompt: Hashable, Codable {
    var message: String
    var images: [RPCImageContent]
    var displayAttachments: [ComposerAttachment]

    var summaryText: String { PromptAttachmentAssembler.summaryText(from: message) }
}

enum AttachmentImportError: LocalizedError, Identifiable {
    case directoryUnsupported(String)
    case unreadable(String)
    case imageDecodeFailed(String)
    case unsupportedPasteboard

    var id: String { localizedDescription }

    var errorDescription: String? {
        switch self {
        case .directoryUnsupported(let name): "Folders aren’t supported yet: \(name)"
        case .unreadable(let name): "Couldn’t read attachment: \(name)"
        case .imageDecodeFailed(let name): "Couldn’t decode image: \(name)"
        case .unsupportedPasteboard: "No supported image or file attachment found."
        }
    }
}

enum AttachmentClassifier {
    static func attachments(from urls: [URL]) -> (attachments: [ComposerAttachment], errors: [AttachmentImportError]) {
        var attachments: [ComposerAttachment] = []
        var errors: [AttachmentImportError] = []
        for url in urls {
            do {
                attachments.append(try attachment(from: url))
            } catch let error as AttachmentImportError {
                errors.append(error)
            } catch {
                errors.append(.unreadable(url.lastPathComponent))
            }
        }
        return (deduplicatingFileReferences(in: attachments), errors)
    }

    static func attachments(from pasteboard: NSPasteboard) -> (attachments: [ComposerAttachment], errors: [AttachmentImportError], didHandle: Bool) {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let result = attachments(from: urls)
            return (result.attachments, result.errors, true)
        }

        if let image = NSImage(pasteboard: pasteboard) {
            do {
                return ([try imageAttachment(from: image, displayName: "Pasted image", sourceURL: nil)], [], true)
            } catch let error as AttachmentImportError {
                return ([], [error], true)
            } catch {
                return ([], [.imageDecodeFailed("Pasted image")], true)
            }
        }

        return ([], [], false)
    }

    static func attachment(from url: URL) throws -> ComposerAttachment {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            throw AttachmentImportError.unreadable(standardized.lastPathComponent)
        }
        if isDirectory.boolValue {
            throw AttachmentImportError.directoryUnsupported(standardized.lastPathComponent)
        }
        guard FileManager.default.isReadableFile(atPath: standardized.path) else {
            throw AttachmentImportError.unreadable(standardized.lastPathComponent)
        }

        if isSupportedImageURL(standardized) {
            let data = try Data(contentsOf: standardized)
            if canSendImageData(data, mimeType: mimeType(for: standardized)) {
                let image = NSImage(data: data)
                return ComposerAttachment(kind: .image(ImageAttachment(
                    data: data,
                    mimeType: mimeType(for: standardized),
                    displayName: standardized.lastPathComponent,
                    sourceURL: standardized,
                    pixelWidth: image.map { Double($0.pixelSize.width) },
                    pixelHeight: image.map { Double($0.pixelSize.height) }
                )))
            }
            guard let image = NSImage(data: data) else {
                throw AttachmentImportError.imageDecodeFailed(standardized.lastPathComponent)
            }
            return try imageAttachment(from: image, displayName: standardized.lastPathComponent, sourceURL: standardized)
        }

        let size = (try? standardized.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        return ComposerAttachment(kind: .fileReference(FileReferenceAttachment(
            url: standardized,
            displayName: standardized.lastPathComponent,
            fileSize: size
        )))
    }

    private static func imageAttachment(from image: NSImage, displayName: String, sourceURL: URL?) throws -> ComposerAttachment {
        guard let data = image.pngData else { throw AttachmentImportError.imageDecodeFailed(displayName) }
        return ComposerAttachment(kind: .image(ImageAttachment(
            data: data,
            mimeType: "image/png",
            displayName: displayName,
            sourceURL: sourceURL,
            pixelWidth: Double(image.pixelSize.width),
            pixelHeight: Double(image.pixelSize.height)
        )))
    }

    private static func deduplicatingFileReferences(in attachments: [ComposerAttachment]) -> [ComposerAttachment] {
        var seen = Set<String>()
        var result: [ComposerAttachment] = []
        for attachment in attachments {
            if case .fileReference(let file) = attachment.kind {
                let key = file.url.standardizedFileURL.path
                guard !seen.contains(key) else { continue }
                seen.insert(key)
            }
            result.append(attachment)
        }
        return result
    }

    private static func isSupportedImageURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff": true
        default: false
        }
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "bmp": "image/bmp"
        case "tif", "tiff": "image/tiff"
        default: "image/png"
        }
    }

    private static func canSendImageData(_ data: Data, mimeType: String) -> Bool {
        guard ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(mimeType) else { return false }
        return NSImage(data: data) != nil
    }
}

enum PromptAttachmentAssembler {
    static func prepare(draft: String, attachments: [ComposerAttachment]) -> PreparedPrompt? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return nil }

        let filePaths = attachments.compactMap { attachment -> String? in
            if case .fileReference(let file) = attachment.kind { return file.url.standardizedFileURL.path }
            return nil
        }
        let images = attachments.compactMap { attachment -> RPCImageContent? in
            if case .image(let image) = attachment.kind {
                return RPCImageContent(mimeType: image.mimeType, data: image.data.base64EncodedString())
            }
            return nil
        }

        var parts: [String] = []
        if !filePaths.isEmpty {
            parts.append("Attached files:\n" + filePaths.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !trimmed.isEmpty {
            if !filePaths.isEmpty {
                parts.append("User message:\n\(trimmed)")
            } else {
                parts.append(trimmed)
            }
        } else if !filePaths.isEmpty {
            parts.append("Please consider the attached file references.")
        } else {
            parts.append("Please consider the attached image\(images.count == 1 ? "" : "s").")
        }

        return PreparedPrompt(message: parts.joined(separator: "\n\n"), images: images, displayAttachments: attachments)
    }

    static func summaryText(from preparedMessage: String) -> String {
        if let range = preparedMessage.range(of: "User message:\n") {
            return String(preparedMessage[range.upperBound...])
        }
        return preparedMessage
    }
}

struct AttachmentChipStrip: View {
    var attachments: [ComposerAttachment]
    var onRemove: ((ComposerAttachment.ID) -> Void)? = nil

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        AttachmentChipView(attachment: attachment, onRemove: onRemove.map { remove in { remove(attachment.id) } })
                    }
                }
                .padding(.vertical, 1)
            }
            .accessibilityIdentifier("composer.attachments")
        }
    }
}

struct AttachmentChipView: View {
    var attachment: ComposerAttachment
    var onRemove: (() -> Void)? = nil
    @State private var isHoveringRemove = false

    var body: some View {
        HStack(spacing: 7) {
            preview
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.displayName)
                    .font(MapleFont.swiftUIFont(size: 12, weight: .medium))
                    .lineLimit(1)
                subtitle
                    .font(MapleFont.swiftUIFont(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(MapleFont.swiftUIFont(size: 11, weight: .bold))
                        .frame(width: 17, height: 17)
                        .background(isHoveringRemove ? Color.primary.opacity(0.14) : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringRemove = $0 }
                .accessibilityLabel("Remove \(attachment.displayName)")
            }
        }
        .padding(6)
        .frame(maxWidth: 230)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12))
        }
    }

    @ViewBuilder private var preview: some View {
        switch attachment.kind {
        case .image(let image):
            if let nsImage = image.nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .frame(width: 34, height: 34)
            }
        case .fileReference:
            Image(systemName: "doc")
                .font(.body)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch attachment.kind {
        case .image(let image):
            if let width = image.pixelWidth, let height = image.pixelHeight {
                Text("\(Int(width))×\(Int(height)) · \(image.mimeType.replacingOccurrences(of: "image/", with: "").uppercased())")
            } else {
                Text(image.mimeType)
            }
        case .fileReference(let file):
            Text(file.fileSize.map(Self.formatBytes) ?? "File reference")
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct PasteAwareTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont = .systemFont(ofSize: 16)
    var textColor: NSColor = .labelColor
    var minHeight: CGFloat = 24
    var maxHeight: CGFloat = 128
    var focusRequest: UUID?
    var textIdentity: AnyHashable?
    var textUpdateRequest: UUID? = nil
    @Environment(\.isEnabled) private var isEnabled
    var onSubmit: () -> Void
    var onHistoryOlder: () -> Bool = { false }
    var onHistoryNewer: () -> Bool = { false }
    var onUserEdit: () -> Void = {}
    var onPasteAttachments: ([ComposerAttachment], [AttachmentImportError]) -> Void
    var onDragTargeted: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        let textView = PasteInterceptingTextView()
        textView.onSubmit = onSubmit
        textView.onHistoryOlder = onHistoryOlder
        textView.onHistoryNewer = onHistoryNewer
        textView.onPasteAttachments = onPasteAttachments
        textView.onDragTargeted = onDragTargeted
        textView.string = text
        textView.delegate = context.coordinator
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = AppTheme.insertionPointNSColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 16, height: 3)
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: maxHeight)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.placeholder = placeholder
        textView.setAccessibilityIdentifier("composer.textEditor")
        scrollView.setAccessibilityIdentifier("composer.textEditor")
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PasteInterceptingTextView else { return }
        context.coordinator.update(text: $text)
        context.coordinator.onUserEdit = onUserEdit
        let identityChanged = textView.representedTextIdentity != textIdentity
        let textUpdateRequested = textView.lastTextUpdateRequest != textUpdateRequest
        let isEditing = scrollView.window?.firstResponder === textView
        let isModelDrivenClear = text.isEmpty && !textView.string.isEmpty
        if textView.string != text && (!isEditing || identityChanged || isModelDrivenClear || textUpdateRequested) {
            textView.isApplyingModelText = true
            textView.string = text
            textView.isApplyingModelText = false
            if textUpdateRequested {
                let end = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                textView.scrollRangeToVisible(NSRange(location: end, length: 0))
            }
        }
        textView.representedTextIdentity = textIdentity
        textView.lastTextUpdateRequest = textUpdateRequest
        textView.placeholder = placeholder
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = AppTheme.insertionPointNSColor
        textView.isEditable = isEnabled
        textView.onSubmit = onSubmit
        textView.onHistoryOlder = onHistoryOlder
        textView.onHistoryNewer = onHistoryNewer
        textView.onPasteAttachments = onPasteAttachments
        textView.onDragTargeted = onDragTargeted
        if textView.lastFocusRequest != focusRequest {
            textView.requestFocus(for: focusRequest)
        }
        textView.invalidateIntrinsicContentSize()
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onUserEdit: () -> Void = {}
        init(text: Binding<String>) { _text = text }
        func update(text: Binding<String>) { _text = text }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            if let textView = textView as? PasteInterceptingTextView,
               !textView.isApplyingModelText {
                onUserEdit()
            }
        }
    }
}

final class PasteInterceptingTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onHistoryOlder: (() -> Bool)?
    var onHistoryNewer: (() -> Bool)?
    var onPasteAttachments: (([ComposerAttachment], [AttachmentImportError]) -> Void)?
    var onDragTargeted: ((Bool) -> Void)?
    var placeholder: String = "" { didSet { needsDisplay = true } }
    var representedTextIdentity: AnyHashable?
    var lastTextUpdateRequest: UUID?
    var lastFocusRequest: UUID?
    private var pendingFocusRequest: UUID?
    var isApplyingModelText = false

    func requestFocus(for request: UUID?) {
        guard lastFocusRequest != request else { return }
        pendingFocusRequest = request
        applyPendingFocusRequest()
        if pendingFocusRequest != nil {
            DispatchQueue.main.async { [weak self] in
                self?.applyPendingFocusRequest()
            }
        }
    }

    private func applyPendingFocusRequest() {
        guard let request = pendingFocusRequest else { return }
        guard let window else { return }
        window.makeFirstResponder(self)
        lastFocusRequest = request
        pendingFocusRequest = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPendingFocusRequest()
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return NSSize(width: NSView.noIntrinsicMetric, height: 24) }
        layoutManager.ensureLayout(for: textContainer)
        let height = max(24, min(128, layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2 + 2))
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func paste(_ sender: Any?) {
        let result = AttachmentClassifier.attachments(from: NSPasteboard.general)
        if result.didHandle {
            onPasteAttachments?(result.attachments, result.errors)
            return
        }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let result = attachmentDropResult(from: sender.draggingPasteboard)
        if result.didHandle {
            onDragTargeted?(true)
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragTargeted?(false)
        super.draggingExited(sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragTargeted?(false)
        super.draggingEnded(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let result = attachmentDropResult(from: sender.draggingPasteboard)
        onDragTargeted?(false)
        if result.didHandle {
            onPasteAttachments?(result.attachments, result.errors)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func attachmentDropResult(from pasteboard: NSPasteboard) -> (attachments: [ComposerAttachment], errors: [AttachmentImportError], didHandle: Bool) {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let result = AttachmentClassifier.attachments(from: urls)
            return (result.attachments, result.errors, true)
        }
        return AttachmentClassifier.attachments(from: pasteboard)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        let disallowedModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        if event.modifierFlags.intersection(disallowedModifiers).isEmpty {
            if event.keyCode == 126, onHistoryOlder?() == true {
                return
            }
            if event.keyCode == 125, onHistoryNewer?() == true {
                return
            }
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, !placeholder.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.placeholderTextColor
            ]
            placeholder.draw(at: NSPoint(x: 0, y: 0), withAttributes: attrs)
        }
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    var pixelSize: CGSize {
        if let rep = representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return size
    }
}
