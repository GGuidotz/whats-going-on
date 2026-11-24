// Colori e vetro, in un posto solo. Le forme, i riempimenti e le molle vengono da Sguardo, il sistema di design comune
// (~/Developer/design-system, compilato insieme all'app da build.sh): qui restano i colori di What's Going On.
// Regola (HIG, Liquid Glass): il vetro solo sui controlli che galleggiano (la barra delle schede, i pulsanti in fondo
// al pannello); il contenuto usa i riempimenti di Sguardo (velo traslucido + filo da 1 pt). Il pannello stesso è un
// popover: su macOS 26 il vetro ce lo mette il sistema. Prima di macOS 26 il vetro diventa un materiale sottile.
// Riduci trasparenza e Aumenta contrasto li gestisce il sistema.

import AppKit
import SwiftUI

enum Palette {
    /// La scala del carico (Sources/Core/ColorScale.swift: rosso-verde o tre colori a scelta), con i toni giusti per
    /// l'aspetto chiaro e per quello scuro.
    static func load(_ severity: Double) -> Color {
        let scale = ColorScale.current
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = scale.rgb(severity, dark: dark)
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        })
    }

    /// Una sfumatura con tutta la scala, da calmo a pieno: per l'anteprima nelle impostazioni.
    static func scaleGradient(_ scale: ColorScale, dark: Bool) -> LinearGradient {
        let colors = stride(from: 0.0, through: 1.0, by: 0.125).map { t -> Color in
            let c = scale.rgb(t, dark: dark)
            return Color(.sRGB, red: c.r, green: c.g, blue: c.b)
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    /// Rete: due colori fuori dalla scala del carico, così download e upload non sembrano allarmi.
    static let download = Color(hue: 0.54, saturation: 0.75, brightness: 0.9)
    static let upload = Color(hue: 0.79, saturation: 0.55, brightness: 0.92)

    /// I colori del marchio, come l'icona: verde calmo e rosso pieno.
    static let calm = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let alarm = Color(red: 0.93, green: 0.26, blue: 0.27)
    static let brand = LinearGradient(colors: [calm, Color(red: 0.98, green: 0.78, blue: 0.25), alarm],
                                      startPoint: .leading, endPoint: .trailing)
}

extension SG.Accent {
    /// L'accento di What's Going On per Sguardo: il verde calmo del marchio (Palette.calm).
    static let whatsGoingOn = SG.Accent(NSColor(srgbRed: 0.20, green: 0.78, blue: 0.45, alpha: 1))
}

extension View {
    /// Vetro per i controlli che galleggiano. Mai per il contenuto. Prima di macOS 26: materiale + velo + filo (Sguardo).
    func glassSurface(in shape: some InsettableShape, interactive: Bool = false) -> some View {
        sgFloatingChrome(in: shape, interactive: interactive)
    }

    /// Pulsante di vetro (secondario), solo nelle barre che galleggiano. Nel contenuto: `.buttonStyle(.sgSecondary)`.
    @ViewBuilder
    func floatingGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Il pulsante principale di una barra che galleggia: vetro colorato. Nel contenuto: `.buttonStyle(.sgPrimary)`.
    @ViewBuilder
    func floatingGlassProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Una scheda del contenuto, come le righe di Sguardo: velo traslucido (più bianco della finestra in chiaro), filo da
    /// 1 pt, angoli continui da 16 pt. Niente vetro (il vetro è dei controlli), niente ombre, niente animazioni.
    func contentCard(padding: CGFloat = 12, radius: CGFloat = SG.Radius.row) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ContentCardBackground(radius: radius))
    }
}

private struct ContentCardBackground: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .sgRowSurface(in: shape)
            .overlay {
                // Aumenta contrasto: un bordo pieno sopra il filo.
                if contrast == .increased { shape.strokeBorder(Color.primary.opacity(0.35), lineWidth: 1) }
            }
    }
}

extension View {
    /// Su macOS 26 la barra in basso diventa una barra di vetro con l'effetto bordo: il contenuto ci scorre sotto e
    /// sfuma. Prima di macOS 26, un normale riquadro in fondo.
    @ViewBuilder
    func floatingBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(macOS 26.0, *) {
            self.safeAreaBar(edge: .bottom, spacing: 0, content: bar)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) { bar().background(.bar) }
        }
    }
}

/// Contenitore dei controlli di vetro: su macOS 26 le forme vicine si fondono e si trasformano insieme.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
