import AppKit
import CoreText
import SwiftUI

enum MapleFont {
    static let preferredPostScriptName = "MapleMono-NF-Regular"
    private static let boldPostScriptName = "MapleMono-NF-Bold"
    private static let italicPostScriptName = "MapleMono-NF-Italic"
    private static let boldItalicPostScriptName = "MapleMono-NF-BoldItalic"

    static func swiftUIFont(size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> Font {
        registerBundledFontsIfNeeded()
        let name = postScriptName(weight: weight, italic: italic)
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: swiftUIWeight(for: weight), design: .monospaced)
    }

    static func nsFont(size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        registerBundledFontsIfNeeded()
        let name = postScriptName(weight: weight, italic: italic)
        return NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func postScriptName(weight: NSFont.Weight, italic: Bool) -> String {
        let isBold = weight.rawValue >= NSFont.Weight.semibold.rawValue
        switch (isBold, italic) {
        case (true, true): return boldItalicPostScriptName
        case (true, false): return boldPostScriptName
        case (false, true): return italicPostScriptName
        case (false, false): return preferredPostScriptName
        }
    }

    private static func swiftUIWeight(for weight: NSFont.Weight) -> Font.Weight {
        switch weight.rawValue {
        case NSFont.Weight.bold.rawValue...: .bold
        case NSFont.Weight.semibold.rawValue...: .semibold
        case NSFont.Weight.medium.rawValue...: .medium
        default: .regular
        }
    }

    private static let bundledFontsRegistered: Void = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("MapleMono-NF-") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    private static func registerBundledFontsIfNeeded() {
        _ = bundledFontsRegistered
    }
}
