// Quanto è carico un valore, da 0 (calmo, verde) a 1 (al limite, rosso): lo usano i colori della barra dei menu e dei
// grafici. Solo numeri: i colori veri li sceglie chi disegna (AppKit nella barra, SwiftUI nel pannello).

import Foundation

enum Severity {
    /// CPU e GPU, 0…1: verde fino al 30%, rosso dal 90%.
    static func load(_ fraction: Double) -> Double { ramp(fraction, 0.3, 0.9) }

    /// Memoria: su macOS una memoria piena all'80% è normale, conta la pressione. Dalla sola occupazione al massimo
    /// arancio; pressione alta almeno arancio, critica rosso.
    static func memory(_ m: MemorySample) -> Double {
        var t = memory(fraction: m.usedFraction)
        if m.pressure == .warning { t = max(t, 0.75) }
        if m.pressure == .critical { t = 1 }
        return t
    }

    static func memory(fraction: Double) -> Double { ramp(fraction, 0.7, 0.98) * 0.6 }

    /// Gradi del chip: verde fino a 55°, rosso da 95°.
    static func temperature(_ celsius: Double) -> Double { ramp(celsius, 55, 95) }

    /// Ciò che resta (spazio libero, carica della batteria), 0…1: verde sopra il 30%, rosso sotto il 5%.
    static func remaining(_ fraction: Double) -> Double { ramp(0.3 - fraction, 0, 0.25) }

    /// Watt dell'intero Mac: verde fino a 8 W, rosso da 40 W.
    static func watts(_ watts: Double) -> Double { ramp(abs(watts), 8, 40) }

    static func ramp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        guard high > low, value.isFinite else { return 0 }
        return min(1, max(0, (value - low) / (high - low)))
    }

    /// Tonalità HSB per la scala: 0,36 verde, 0,17 giallo, 0 rosso.
    static func hue(_ severity: Double) -> Double { 0.36 * (1 - min(1, max(0, severity))) }
}
