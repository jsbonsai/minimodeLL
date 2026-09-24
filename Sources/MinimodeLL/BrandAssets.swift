import AppKit
import CoreText
import SwiftUI
import LocalAgentCore

/// Curated brand resources work in both the signed app and SwiftPM development runs.
@MainActor enum BrandAssets {
    static let directory: URL = {
        if let packaged = Bundle.main.resourceURL?.appendingPathComponent("BrandAssets"),
           FileManager.default.fileExists(atPath: packaged.path) { return packaged }
        return Bundle.module.url(forResource: "BrandAssets", withExtension: nil)!
    }()

    static func registerFonts() {
        for name in ["Geist-Regular", "Geist-Bold", "Geist-SemiBold", "GeistMono-Regular"] {
            CTFontManagerRegisterFontsForURL(directory.appendingPathComponent(name + ".otf") as CFURL, .process, nil)
        }
    }

    static func menuIcon(_ state: MinimodeMark.State) -> NSImage {
        switch state {
        case .active: activeIcon
        case .idle: idleIcon
        case .off: offIcon
        }
    }
    private static let activeIcon = template("MenuBarIconTemplate")
    private static let idleIcon = template("MenuBarIconIdleTemplate")
    private static let offIcon = template("MenuBarIconOffTemplate")
    private static func template(_ name: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for suffix in ["", "@2x", "@3x"] {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(name + suffix + ".png")),
               let representation = NSBitmapImageRep(data: data) {
                image.addRepresentation(representation)
            }
        }
        image.isTemplate = true
        return image
    }

    /// Read the supplied light/dark color definitions instead of duplicating their RGB values.
    static func color(_ name: String) -> Color {
        struct Catalog: Decodable {
            struct Entry: Decodable {
                struct Appearance: Decodable { let appearance: String; let value: String }
                struct RGB: Decodable { let components: [String: String] }
                let appearances: [Appearance]?
                let color: RGB
            }
            let colors: [Entry]
        }
        let catalog = try! JSONDecoder().decode(Catalog.self, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
        let light = catalog.colors.first { $0.appearances == nil }!
        let dark = catalog.colors.first { $0.appearances?.contains(where: { $0.value == "dark" }) == true } ?? light
        func rgba(_ entry: Catalog.Entry) -> NSColor {
            let c = entry.color.components
            func component(_ name: String) -> Double {
                let value = c[name]!
                if value.hasPrefix("0x") { return Double(Int(value.dropFirst(2), radix: 16)!) / 255 }
                return Double(value)!
            }
            return NSColor(srgbRed: component("red"), green: component("green"),
                           blue: component("blue"), alpha: component("alpha"))
        }
        let lightColor = rgba(light), darkColor = rgba(dark)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        })
    }
}

@MainActor extension Color {
    static let mmInk = BrandAssets.color("BrandInk")
    static let mmSurface = BrandAssets.color("BrandSurface")
    static let mmMuted = BrandAssets.color("BrandMuted")
    static let mmAccent = BrandAssets.color("AccentColor")
}

struct BrandLockup: View {
    let state: MinimodeMark.State
    private var name: String { Brand.displayName }
    var body: some View {
        HStack(spacing: 9) {
            MinimodeMark(state: state).frame(width: 30, height: 30)
                .accessibilityHidden(true)
            if name.hasSuffix("LL") {
                (Text(String(name.dropLast(2))).font(.custom("Geist-Regular", size: 21))
                 + Text("LL").font(.custom("Geist-Bold", size: 21)).foregroundColor(.mmAccent))
            } else { Text(name).font(.custom("Geist-Regular", size: 21)) }
        }
        .foregroundStyle(Color.mmInk)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

extension AppState {
    /// Application task state only. Runtime health is not observed by the current preview.
    var brandState: MinimodeMark.State { busy ? .active : (snapshot == nil ? .off : .idle) }
}
