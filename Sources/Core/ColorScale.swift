// La scala dei colori del carico, scelta nelle impostazioni: rosso-verde (predefinita) o tre colori a scelta (di
// partenza verde, bianco, rosso). Solo numeri sRGB 0…1: AppKit e SwiftUI ne fanno i loro colori. Sulla barra chiara i
// colori troppo chiari si scuriscono e sulla barra scura quelli troppo scuri si schiariscono, così restano leggibili.

import Foundation

/// Un colore sRGB, componenti 0…1.
struct RGB: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    static let green = RGB(r: 0.20, g: 0.80, b: 0.36)
    static let white = RGB(r: 1, g: 1, b: 1)
    static let red = RGB(r: 0.94, g: 0.24, b: 0.22)

    /// Da tonalità, saturazione e luminosità (HSB), tutte 0…1.
    init(hue: Double, saturation s: Double, brightness v: Double) {
        let h = (hue - floor(hue)) * 6
        let i = Int(h) % 6, f = h - floor(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let c: (Double, Double, Double)
        switch i {
        case 0: c = (v, t, p)
        case 1: c = (q, v, p)
        case 2: c = (p, v, t)
        case 3: c = (p, q, v)
        case 4: c = (t, p, v)
        default: c = (v, p, q)
        }
        self.init(r: c.0, g: c.1, b: c.2)
    }

    init(r: Double, g: Double, b: Double) {
        self.r = min(1, max(0, r))
        self.g = min(1, max(0, g))
        self.b = min(1, max(0, b))
    }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// Luminanza relativa (WCAG), 0 nero … 1 bianco.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}

struct ColorScale: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case redGreen, threeColors
        var id: String { rawValue }
        var title: String {
            switch self {
            case .redGreen: L("Rosso-verde")
            case .threeColors: L("Tre colori")
            }
        }
    }

    var kind: Kind = .redGreen
    /// Carico basso, medio e al limite.
    var low: RGB = .green
    var mid: RGB = .white
    var high: RGB = .red

    /// La scala in uso, per chi disegna senza ricevere le preferenze (il pannello). La imposta l'app.
    nonisolated(unsafe) static var current = ColorScale()

    /// Il colore per una gravità 0…1, su una superficie scura (`dark`) o chiara.
    func rgb(_ severity: Double, dark: Bool) -> RGB {
        let t = min(1, max(0, severity.isFinite ? severity : 0))
        switch kind {
        case .redGreen:
            // verde, giallo, arancio, rosso: colori pieni, un po' più chiari sulla barra scura
            return Self.legible(RGB(hue: Severity.hue(t), saturation: dark ? 0.74 : 0.95, brightness: dark ? 1 : 0.7),
                                dark: dark)
        case .threeColors:
            let raw = t < 0.5 ? low.mixed(with: mid, t * 2) : mid.mixed(with: high, (t - 0.5) * 2)
            return Self.legible(raw, dark: dark)
        }
    }

    /// Scurisce i colori troppo chiari su fondo chiaro (il bianco diventa grigio) e schiarisce quelli troppo scuri su
    /// fondo scuro. Contrasto di almeno 3:1 circa, quello del testo in grassetto.
    static func legible(_ c: RGB, dark: Bool) -> RGB {
        var out = c
        if dark {
            for _ in 0..<10 where out.luminance < 0.16 { out = out.mixed(with: .white, 0.15) }
        } else {
            for _ in 0..<10 where out.luminance > 0.22 { out = RGB(r: out.r * 0.9, g: out.g * 0.9, b: out.b * 0.9) }
        }
        return out
    }
}
