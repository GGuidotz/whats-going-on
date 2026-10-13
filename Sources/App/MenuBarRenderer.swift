// Ciò che si vede nella barra dei menu, disegnato con AppKit: per ogni misura una sigla scritta in verticale (CPU, RAM,
// RETE…) e il valore accanto, colorato sulla scala del carico (verde, giallo, arancio, rosso). La rete ha due righe,
// upload sopra e download sotto, con due colori fuori dalla scala e la freccia davanti: il colore non è mai l'unico
// segnale. Ogni voce ha una larghezza fissa e cifre tabellari, così la barra non si sposta quando i numeri cambiano.
// L'immagine non è un modello (template): i colori li sceglie l'app, in base all'aspetto della barra (chiara o scura).

import AppKit

struct MenuBarEntry {
    struct Bar {
        /// 0…1
        var height: Double
        var severity: Double
    }

    enum Content {
        /// Un numero con la sua unità piccola ("42" "%"); `template` è il numero più largo previsto, per la larghezza fissa.
        case gauge(number: String, unit: String, template: String, severity: Double, bars: [Bar])
        case network(up: String, down: String, upActive: Bool, downActive: Bool)
    }

    var module: MenuBarModule
    var label: String
    var content: Content
}

enum MenuBarRenderer {
    static let height: CGFloat = 22
    private static let barCount = 12

    private static let labelFont = NSFont.systemFont(ofSize: 7, weight: .bold, width: .condensed)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
    private static let unitFont = NSFont.systemFont(ofSize: 8, weight: .bold)
    private static let networkFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)

    // MARK: - Dati

    /// Le voci da disegnare, solo per i moduli che questo Mac fornisce.
    static func entries(_ modules: [MenuBarModule], snapshot s: Snapshot, history h: History, graphs: Bool) -> [MenuBarEntry] {
        func bars(_ metric: Metric, scale: Double = 1, severity: (Double) -> Double) -> [MenuBarEntry.Bar] {
            guard graphs else { return [] }
            return h.recent(metric, barCount).map { MenuBarEntry.Bar(height: min(1, max(0, $0 / scale)), severity: severity($0)) }
        }
        func percent(_ fraction: Double) -> String { "\(Int((max(0, fraction) * 100).rounded()))" }

        return modules.compactMap { m -> MenuBarEntry? in
            switch m {
            case .cpu:
                guard let c = s.cpu else { return nil }
                return MenuBarEntry(module: m, label: L("CPU"), content: .gauge(
                    number: percent(c.total), unit: "%", template: "100", severity: Severity.load(c.total),
                    bars: bars(.cpu, severity: Severity.load)))
            case .memory:
                guard let mem = s.memory else { return nil }
                return MenuBarEntry(module: m, label: L("RAM"), content: .gauge(
                    number: percent(mem.usedFraction), unit: "%", template: "100", severity: Severity.memory(mem),
                    bars: bars(.memory) { Severity.memory(fraction: $0) }))
            case .network:
                guard let n = s.network else { return nil }
                return MenuBarEntry(module: m, label: L("RETE"), content: .network(
                    up: Format.compactRate(n.upload), down: Format.compactRate(n.download),
                    upActive: n.upload >= 1000, downActive: n.download >= 1000))
            case .temperature:
                guard let chip = s.sensors?.chip else { return nil }
                return MenuBarEntry(module: m, label: L("TEMP"), content: .gauge(
                    number: "\(Int(chip.rounded()))", unit: "°", template: "100", severity: Severity.temperature(chip),
                    bars: bars(.temperature, scale: 110, severity: Severity.temperature)))
            case .gpu:
                guard let g = s.gpu else { return nil }
                return MenuBarEntry(module: m, label: L("GPU"), content: .gauge(
                    number: percent(g.utilization), unit: "%", template: "100", severity: Severity.load(g.utilization),
                    bars: bars(.gpu, severity: Severity.load)))
            case .disk:
                guard let d = s.disk else { return nil }
                let text = Format.compactBytes(d.free)
                return MenuBarEntry(module: m, label: L("SSD"), content: .gauge(
                    number: String(text.dropLast()), unit: String(text.suffix(1)), template: "999",
                    severity: Severity.remaining(d.freeFraction), bars: []))
            case .power:
                guard let w = s.sensors?.systemWatts ?? s.battery?.watts else { return nil }
                let peak = max(h.recent(.power, barCount).max() ?? 0, 1)
                return MenuBarEntry(module: m, label: L("WATT"), content: .gauge(
                    number: "\(Int(abs(w).rounded()))", unit: "", template: "99", severity: Severity.watts(w),
                    bars: bars(.power, scale: peak, severity: Severity.watts)))
            }
        }
    }

    /// Per VoiceOver e per il suggerimento al passaggio del puntatore.
    static func spokenLabel(_ entries: [MenuBarEntry]) -> String {
        entries.map { e in
            switch e.content {
            case let .gauge(number, unit, _, _, _):
                return "\(e.module.title) \(number)\(unit.isEmpty ? " W" : unit)"
            case let .network(up, down, _, _):
                return L("Rete: download %@, upload %@", down, up)
            }
        }
        .joined(separator: ", ")
    }

    // MARK: - Disegno

    /// L'immagine per la barra. `dark` = la barra è scura (testo chiaro).
    static func image(_ entries: [MenuBarEntry], dark: Bool) -> NSImage {
        let widths = entries.map(width)
        let spacing: CGFloat = 8
        let total = max(1, widths.reduce(0, +) + spacing * CGFloat(max(0, entries.count - 1)) + 2)
        let image = NSImage(size: NSSize(width: ceil(total), height: height), flipped: false) { _ in
            var x: CGFloat = 1
            for (entry, w) in zip(entries, widths) {
                draw(entry, at: x, dark: dark)
                x += w + spacing
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = spokenLabel(entries)
        return image
    }

    private static func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static var labelColumn: CGFloat { ceil(labelFont.capHeight) + 2 }

    private static func width(_ entry: MenuBarEntry) -> CGFloat {
        switch entry.content {
        case let .gauge(number, unit, template, _, bars):
            let numberWidth = max(textWidth(template, valueFont), textWidth(number, valueFont))
            let unitWidth = unit.isEmpty ? 0 : textWidth(unit, unitFont) + 0.5
            let graph: CGFloat = bars.isEmpty ? 0 : CGFloat(barCount) * 1.5 + 2
            return labelColumn + 2 + graph + numberWidth + unitWidth
        case let .network(up, down, _, _):
            let numbers = max(textWidth("999K", networkFont), textWidth(up, networkFont), textWidth(down, networkFont))
            return labelColumn + 2 + textWidth("↓", networkFont) + 1.5 + numbers
        }
    }

    private static func draw(_ entry: MenuBarEntry, at x: CGFloat, dark: Bool) {
        let labelColor = dark ? NSColor(white: 1, alpha: 0.72) : NSColor(white: 0, alpha: 0.6)
        drawVerticalLabel(entry.label, centerX: x + labelColumn / 2, color: labelColor)
        var cursor = x + labelColumn + 2

        switch entry.content {
        case let .gauge(number, unit, template, severity, bars):
            if !bars.isEmpty {
                let start = cursor + CGFloat(barCount - bars.count) * 1.5
                for (i, bar) in bars.enumerated() {
                    let h = max(1, CGFloat(bar.height) * 14)
                    scaleColor(bar.severity, dark: dark).withAlphaComponent(0.9).setFill()
                    NSBezierPath(roundedRect: NSRect(x: start + CGFloat(i) * 1.5, y: 4, width: 1, height: h),
                                 xRadius: 0.5, yRadius: 0.5).fill()
                }
                cursor += CGFloat(barCount) * 1.5 + 2
            }
            let color = scaleColor(severity, dark: dark)
            let numberWidth = max(textWidth(template, valueFont), textWidth(number, valueFont))
            let baseline = height / 2 - valueFont.capHeight / 2
            drawText(number, font: valueFont, color: color,
                     x: cursor + numberWidth - textWidth(number, valueFont), baseline: baseline)
            if !unit.isEmpty {
                drawText(unit, font: unitFont, color: color.withAlphaComponent(0.8), x: cursor + numberWidth + 0.5, baseline: baseline)
            }

        case let .network(up, down, upActive, downActive):
            let arrowWidth = textWidth("↓", networkFont) + 1.5
            let numbers = max(textWidth("999K", networkFont), textWidth(up, networkFont), textWidth(down, networkFont))
            let right = cursor + arrowWidth + numbers
            let half = networkFont.capHeight / 2
            let rows: [(String, String, Bool, NSColor, CGFloat)] = [
                ("↑", up, upActive, uploadColor(dark: dark), height * 0.74 - half),
                ("↓", down, downActive, downloadColor(dark: dark), height * 0.26 - half),
            ]
            for (arrow, value, active, tint, baseline) in rows {
                let color = active ? tint : labelColor.withAlphaComponent(dark ? 0.5 : 0.45)
                drawText(arrow, font: networkFont, color: color, x: cursor, baseline: baseline)
                drawText(value, font: networkFont, color: color, x: right - textWidth(value, networkFont), baseline: baseline)
            }
        }
    }

    /// Scrive `text` con la linea di base a `baseline` (coordinate con l'origine in basso).
    private static func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, baseline: CGFloat) {
        (text as NSString).draw(at: NSPoint(x: x, y: baseline + font.descender),
                                withAttributes: [.font: font, .foregroundColor: color])
    }

    /// La sigla girata di 90°: si legge dal basso verso l'alto, come sul dorso di un libro.
    private static func drawVerticalLabel(_ text: String, centerX: CGFloat, color: NSColor) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: color, .kern: 0.4]
        let size = (text as NSString).size(withAttributes: attributes)
        cg.saveGState()
        cg.translateBy(x: centerX, y: height / 2)
        cg.rotate(by: .pi / 2)
        (text as NSString).draw(at: NSPoint(x: -size.width / 2, y: -labelFont.capHeight / 2 + labelFont.descender),
                                withAttributes: attributes)
        cg.restoreGState()
    }

    // MARK: - Colori

    /// La scala del carico, più chiara sulla barra scura e più scura sulla barra chiara, per restare leggibile.
    static func scaleColor(_ severity: Double, dark: Bool) -> NSColor {
        NSColor(calibratedHue: Severity.hue(severity), saturation: dark ? 0.6 : 0.92, brightness: dark ? 1 : 0.66, alpha: 1)
    }

    static func downloadColor(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedHue: 0.53, saturation: 0.55, brightness: 1, alpha: 1)
             : NSColor(calibratedHue: 0.57, saturation: 0.95, brightness: 0.78, alpha: 1)
    }

    static func uploadColor(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedHue: 0.79, saturation: 0.42, brightness: 1, alpha: 1)
             : NSColor(calibratedHue: 0.78, saturation: 0.72, brightness: 0.78, alpha: 1)
    }
}
