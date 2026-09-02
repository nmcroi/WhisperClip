import SwiftUI

/// De ene knoppentaal van de app, afgesproken met Niels op 13 augustus 2026.
///
/// Vier soorten bediening, elk met één vaste vorm:
/// 1. Ga ergens heen: witte regel met een pijltje rechts (NavigationLink of rij
///    met chevron), ook voor uitleg-vensters.
/// 2. Kies hier: witte tekst links, gele waarde rechts (inline Picker).
/// 3. Aan of uit: Toggle met `Theme.accent`-tint.
/// 4. Doe iets nu: ALTIJD een knop met vorm, dit bestand. Kale gele
///    tekstregels bestaan niet meer.
///
/// Kernregel: geel is een gekozen waarde of een knop met vorm; al het andere is
/// wit met een teken rechts dat zegt wat er gaat gebeuren.
enum ActionButtonRole {
    /// Geel gevuld. Maximaal één per scherm: de hoofdactie.
    case primary
    /// Omrand op een kaartvlak. Alle overige acties.
    case secondary
    /// Voor verwijderen en andere onomkeerbare acties.
    case destructive
}

enum ActionButtonSize {
    /// 16pt semibold, verticale padding 12, volle breedte. Losstaande knoppen.
    case regular
    /// 12pt semibold, verticale padding 8. Actiebalken en bedieningsrijen.
    case compact
}

/// Het label: los bruikbaar in `Menu` en `ShareLink`, die hun eigen knop zijn.
struct ActionButtonLabel: View {
    let title: String
    var systemImage: String?
    var role: ActionButtonRole = .secondary
    var size: ActionButtonSize = .regular
    /// Uitgegrijsd wanneer de knop niets kan doen (bijv. lege selectie).
    var isEnabled = true

    var body: some View {
        label
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, size == .regular ? 12 : 8)
            .padding(.horizontal, size == .regular ? 12 : 8)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                    .stroke(border, lineWidth: role == .primary ? 0 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
            .contentShape(Rectangle())
    }

    /// Tekst wordt NOOIT afgebroken (regel van Niels, 13 aug 2026). Compacte
    /// knoppen zetten daarom het icoon bóven de tekst, zodat het label de volle
    /// knopbreedte heeft; knelt het dan nog, dan schaalt de tekst kleiner.
    @ViewBuilder
    private var label: some View {
        switch size {
        case .regular:
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(ThemeFont.ui(16, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        case .compact:
            VStack(spacing: 3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(ThemeFont.ui(12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.textTertiary }
        switch role {
        case .primary: return Theme.onAccent
        case .secondary: return Theme.accentText
        case .destructive: return Theme.danger
        }
    }

    private var background: Color {
        guard isEnabled else {
            return role == .primary ? Theme.surfaceHover : Theme.surface
        }
        switch role {
        case .primary: return Theme.accent
        case .secondary: return Theme.surface
        case .destructive: return Theme.dangerSoft
        }
    }

    private var border: Color {
        switch role {
        case .primary: return .clear
        case .secondary: return Theme.border
        case .destructive: return Theme.danger.opacity(0.35)
        }
    }
}

/// Proefstijl (13 aug 2026, wens van Niels): de knop ís het icoon. Groot geel
/// icoon met de tekst in wit eronder, zonder kader. Draait eerst op één pagina
/// (het Geschiedenis-detail) ter beoordeling; bevalt hij, dan wordt dit de
/// standaard voor actiebalken.
struct IconActionLabel: View {
    let title: String
    let systemImage: String
    /// Geel voor gewone acties, `Theme.danger` voor verwijderen.
    var iconColor: Color = Theme.accentText
    /// De tekst is gedempt; alleen een actieve stand (zoals het AI-paneel
    /// open) mag hem geel kleuren.
    var isActive = false
    /// Uitgegrijsd wanneer de knop niets kan doen (bijv. lege selectie).
    var isEnabled = true

    var body: some View {
        VStack(spacing: 5) {
            // Vast icoonvak: SF-symbolen verschillen in hoogte (een kruisje is
            // lager dan een prullenbak), waardoor de labels niet op één lijn
            // stonden (13 aug 2026).
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isEnabled ? iconColor : Theme.textTertiary)
                .frame(height: 28)
            Text(title)
                .font(ThemeFont.ui(10, weight: .medium))
                .foregroundStyle(
                    !isEnabled ? Theme.textTertiary
                        : isActive ? Theme.accentText
                        : Theme.textSecondary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

#if os(iOS)
/// De ene sluitknop van elke sheet: een geel kruisje rechtsboven in de
/// navigatiebalk. Daarvoor stond er op de ene sheet "Annuleer" linksboven, op de
/// andere "Gereed" rechtsboven en op `AssignNoteSheet` helemaal niets, waardoor
/// die alleen weg te vegen was (2 sep 2026).
struct SheetCloseToolbar: ViewModifier {
    let label: String
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
            }
        }
    }
}

extension View {
    /// Zet de vaste sluitknop rechtsboven op een sheet. `label` is de
    /// voorleestekst, in de taal van de app.
    func sheetCloseButton(label: String, onClose: @escaping () -> Void) -> some View {
        modifier(SheetCloseToolbar(label: label, onClose: onClose))
    }
}
#endif

/// De knop zelf. `.buttonStyle(.plain)` zit erin, zodat de vorm in een List of
/// Form niet door de rij-stijl wordt overschreven.
struct ActionButton: View {
    let title: String
    var systemImage: String?
    var role: ActionButtonRole = .secondary
    var size: ActionButtonSize = .regular
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionButtonLabel(
                title: title,
                systemImage: systemImage,
                role: role,
                size: size,
                isEnabled: isEnabled
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
