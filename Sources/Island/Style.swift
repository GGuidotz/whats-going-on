// Colori e vetro, in un posto solo.
// Regola (HIG, Liquid Glass): il vetro solo sui controlli che galleggiano (la barra delle schede, i pulsanti in fondo
// al pannello); il contenuto usa riempimenti standard. Il pannello stesso è un popover: su macOS 26 il vetro ce lo mette
// il sistema. Prima di macOS 26 il vetro diventa un materiale sottile. Riduci trasparenza e Aumenta contrasto li
// gestisce il sistema.

import SwiftUI

enum Palette {
    /// La scala del carico: verde, giallo, arancio, rosso (Sources/Core/Severity.swift).
    static func load(_ severity: Double) -> Color {
        Color(hue: Severity.hue(severity), saturation: 0.8, brightness: 0.84)
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

extension View {
    /// Vetro per i controlli che galleggiano. Mai per il contenuto.
    @ViewBuilder
    func glassSurface(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Pulsante di vetro (secondario).
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Il pulsante principale, uno per vista: vetro colorato.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Una scheda del contenuto: riempimento standard (non vetro), angoli ampi.
    func contentCard(padding: CGFloat = 12, radius: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
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
