import Core
import SwiftUI
import UIKit

// MARK: - Appearance mapping

extension AppSettings.AppearanceMode {
    /// The SwiftUI colour scheme to force via `.preferredColorScheme(_:)`.
    /// `.system` returns `nil` so the app follows iOS.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    /// Localized label for the appearance picker.
    func label(in language: AppLanguage) -> String {
        switch self {
        case .system: return L10n.string( "Systeem", locale: language.locale)
        case .dark: return L10n.string( "Donker", locale: language.locale)
        case .light: return L10n.string( "Licht", locale: language.locale)
        }
    }
}

// MARK: - Hex helper

extension Color {
    /// Creates a color from a 6-digit hex string (e.g. `"0E0E10"` or `"#0E0E10"`).
    init(hex: String) {
        let (r, g, b) = Color.rgbComponents(hex: hex)
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Parses a 6-digit hex string into sRGB components in `0...1`.
    fileprivate static func rgbComponents(hex: String) -> (Double, Double, Double) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        return (r, g, b)
    }

    /// A **dynamic** color that resolves to `lightHex` under a light appearance
    /// and `darkHex` under a dark appearance. Backed by a `UIColor` dynamic
    /// provider so a single token follows the active trait collection, call
    /// sites use the same `Theme.xxx` tokens as the mac app, so views read
    /// identically across platforms.
    init(lightHex: String, darkHex: String) {
        let light = Color.uiColor(hex: lightHex)
        let dark = Color.uiColor(hex: darkHex)
        let dynamic = UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
        self.init(uiColor: dynamic)
    }

    /// An sRGB `UIColor` from a 6-digit hex string.
    fileprivate static func uiColor(hex: String) -> UIColor {
        let (r, g, b) = rgbComponents(hex: hex)
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Merkthema

/// Het merk waarin de app zich toont. WhisperClip is het eigen geel-zwart;
/// GHX gebruikt de officiële huisstijl (Impact Blue #001473, Innovation
/// Orange #FF5E1A) voor de demo aan GHX (13 aug 2026). Alleen de
/// accentkleuren wisselen; opmaak, gedrag en naam blijven identiek.
/// GHX-naam en huisstijl alleen tonen aan GHX zelf tot zij toestemming geven.
enum AppBrand: String, CaseIterable, Identifiable {
    case whisperClip
    case ghx

    var id: String { rawValue }

    func label(in language: AppLanguage) -> String {
        switch self {
        case .whisperClip: return "WhisperClip"
        case .ghx: return "GHX"
        }
    }
}

/// The v2 design language ported to iOS: sleek, tight, **yellow** as the primary
/// accent and **red** as the secondary/recording accent. Hex values are
/// byte-identical to the mac `Theme` so both apps share one visual identity.
///
/// Every token is **appearance-aware** via ``SwiftUI/Color/init(lightHex:darkHex:)``.
/// Dark is the signature look and the default; light mirrors it for opt-in users.
enum Theme {

    /// Het actieve merk. Gezet door `AppModel` bij start en bij wisselen in
    /// Instellingen; elke wijziging van een `@Published` op het model tekent de
    /// schermen opnieuw, dus de kleuren volgen direct. `nonisolated(unsafe)`
    /// omdat de kleur-getters vanuit View-body's lezen: in de praktijk raakt
    /// alleen de main thread dit, net als de Views zelf.
    nonisolated(unsafe) static var brand: AppBrand = .whisperClip

    // MARK: Surfaces

    /// App background. GHX: True Blue #091431, door de gids goedgekeurd voor
    /// grote digitale vlakken; licht een vleug blauw-wit.
    static var window: Color {
        brand == .ghx
            ? Color(lightHex: "F7FAFF", darkHex: "091431")
            : Color(lightHex: "FBFBFA", darkHex: "0E0E10")
    }
    /// Card / raised surface.
    static var surface: Color {
        brand == .ghx
            ? Color(lightHex: "FFFFFF", darkHex: "101D4A")
            : Color(lightHex: "FFFFFF", darkHex: "17171A")
    }
    /// Slightly lifted surface (hover, selected rows, input fields).
    static var surfaceHover: Color {
        brand == .ghx
            ? Color(lightHex: "EAF0FB", darkHex: "182861")
            : Color(lightHex: "F1F1EF", darkHex: "1F1F23")
    }
    /// Subtle 1px border.
    static var border: Color {
        brand == .ghx
            ? Color(lightHex: "D7E0F5", darkHex: "20306E")
            : Color(lightHex: "E3E3DF", darkHex: "26262B")
    }
    /// Brighter border for hover / focus.
    static var borderStrong: Color {
        brand == .ghx
            ? Color(lightHex: "B9C8EC", darkHex: "2E4088")
            : Color(lightHex: "D0D0CB", darkHex: "35353C")
    }

    // MARK: Text

    /// Primary text. GHX licht: diep blauw in plaats van zwart, zoals de gids
    /// zijn lopende tekst zet.
    static var text: Color {
        brand == .ghx
            ? Color(lightHex: "0B1B4D", darkHex: "F5F7FF")
            : Color(lightHex: "111114", darkHex: "F5F5F7")
    }
    /// Secondary / muted text.
    static var textSecondary: Color {
        brand == .ghx
            ? Color(lightHex: "4A5A8C", darkHex: "9FACD8")
            : Color(lightHex: "57575C", darkHex: "9A9AA2")
    }
    /// Tertiary / faint text (timecodes, captions).
    static var textTertiary: Color {
        brand == .ghx
            ? Color(lightHex: "6C7BA6", darkHex: "7583B4")
            : Color(lightHex: "6F6F75", darkHex: "7F7F88")
    }

    // MARK: Accents

    /// Primary accent for **fills / highlights**: the "Kopieer" button, level
    /// bars, the record ring. GHX: Innovation Orange, keuze van Niels
    /// (13 aug 2026); witte tekst erop, zoals de gids op oranje vlakken doet.
    static var accent: Color {
        brand == .ghx
            ? Color(lightHex: "FF5E1A", darkHex: "FF5E1A")
            : Color(lightHex: "FFD60A", darkHex: "FFD60A")
    }
    /// Accent for **text / thin strokes / iconen**. GHX: Innovation Orange,
    /// op wens van Niels (13 aug 2026); "graphics & text safe" in de gids.
    static var accentText: Color {
        brand == .ghx
            ? Color(lightHex: "E04A0E", darkHex: "FF5E1A")
            : Color(lightHex: "8A6900", darkHex: "FFD60A")
    }
    /// A dimmer accent for large fills / hovers.
    static var accentSoft: Color {
        brand == .ghx
            ? Color(lightHex: "CC4B15", darkHex: "CC4B15")
            : Color(lightHex: "C9A800", darkHex: "C9A800")
    }
    /// Secondary accent: recording state, destructive actions. GHX: een
    /// donkerder, koeler rood (kardinaalrood) in plaats van Spark Red #FF0000,
    /// want dat lag te dicht tegen Innovation Orange aan (13 aug 2026).
    static var danger: Color {
        brand == .ghx
            ? Color(lightHex: "8C0B1F", darkHex: "A50D24")
            : Color(lightHex: "C91F18", darkHex: "FF453A")
    }
    /// A dimmer red for backgrounds.
    static let dangerSoft = Color(lightHex: "FBE4E2", darkHex: "3A1A18")

    /// Foreground color to place on top of the accent fill. Donker op geel;
    /// wit op GHX-blauw, zoals de gids witte tekst op blauwe vlakken zet.
    static var onAccent: Color {
        brand == .ghx
            ? Color(lightHex: "FFFFFF", darkHex: "FFFFFF")
            : Color(lightHex: "0E0E10", darkHex: "0E0E10")
    }

    /// Het kleine merkaccent: de punt in het woordmerk. GHX: Innovation Orange
    /// #FF5E1A, het accent van de X, bewust spaarzaam gebruikt.
    static var wordmarkDot: Color {
        brand == .ghx
            ? Color(lightHex: "FF5E1A", darkHex: "FF5E1A")
            : accentText
    }

    // MARK: Metrics

    enum Metrics {
        static let radius: CGFloat = 8
        static let cardRadius: CGFloat = 12
        static let hairline: CGFloat = 1
    }
}

// MARK: - Typography

/// Font helpers. UI uses bundled Inter throughout; Merriweather is available for
/// the app-title wordmark only. Falls back to the system sans / serif when the
/// bundled families are unavailable.
enum ThemeFont {
    static let hasInter = fontFamilyIsAvailable("Inter")
    static let hasMerriweather = fontFamilyIsAvailable("Merriweather")

    /// Inter for all UI text.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let style = relativeStyle(for: size)
        if hasInter {
            return .custom("Inter", size: size, relativeTo: style).weight(weight)
        }
        return .system(style, design: .default).weight(weight)
    }

    /// Merriweather for the app-title wordmark only; falls back to Inter/system.
    static func wordmark(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        if hasMerriweather {
            return .custom(
                "Merriweather",
                size: size,
                relativeTo: relativeStyle(for: size)
            ).weight(weight)
        }
        return ui(size, weight: weight)
    }

    /// Koppelt de visuele puntgrootte aan een semantische Dynamic Type-stijl.
    /// Zo blijft de bestaande hiërarchie intact, terwijl alle eigen Inter- en
    /// Merriweather-tekst meegroeit met de toegankelijkheidsinstelling.
    private static func relativeStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 32...: .largeTitle
        case 26...: .title
        case 21...: .title2
        case 19...: .title3
        case 17...: .body
        case 15...: .subheadline
        case 13...: .footnote
        default: .caption2
        }
    }

    private static func fontFamilyIsAvailable(_ family: String) -> Bool {
        // UIFont exposes families with the bundled PostScript family name once the
        // UIAppFonts entries are registered at launch.
        UIFont.familyNames.contains(family)
    }
}

// MARK: - Reusable view helpers

extension View {
    /// A standard card surface: fill, 1px border, rounded corners.
    func themeCard(radius: CGFloat = Theme.Metrics.cardRadius, border: Color = Theme.border) -> some View {
        self
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: Theme.Metrics.hairline)
            )
    }
}

/// The app-title wordmark: "WhisperClip" with an accent period. In het
/// GHX-thema staat hier het officiële GHX-logo (wens van Niels, 13 aug 2026):
/// uit de Brand Guide geknipt, wit met oranje X op donker en blauw met oranje
/// X op licht, nooit hertekend of vervormd (logoregels in de skill ghx-stijl).
struct Wordmark: View {
    var size: CGFloat = 26

    var body: some View {
        if Theme.brand == .ghx {
            Image("GHXLogo")
                .resizable()
                .scaledToFit()
                .frame(height: size * 1.45)
                .accessibilityLabel("GHX")
        } else {
            Text.accentDotted("WhisperClip")
                .font(ThemeFont.wordmark(size, weight: .bold))
        }
    }
}

/// De vaste grote paginatitel onder het gecentreerde Whisper Clip-woordmerk.
struct MainPageHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack {
            Text(title)
                .font(ThemeFont.ui(34, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

extension Text {
    /// The brand heading pattern: "<title>." with the trailing period in the
    /// accent colour.
    static func accentDotted(_ title: String) -> Text {
        Text(verbatim: title).foregroundStyle(Theme.text)
            + Text(verbatim: ".").foregroundStyle(Theme.wordmarkDot)
    }
}
