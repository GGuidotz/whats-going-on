// Il grafico degli ultimi istanti: una linea con un'area leggera sotto. Scorre da destra, come il tempo.
// Lo leggono gli occhi, non VoiceOver: il valore e la tendenza li porta l'etichetta della riga.
// Un solo Canvas: a pannello aperto si ridisegna ogni secondo, e una vista sola costa molto meno di tante forme.

import SwiftUI

struct Sparkline: View {
    var values: [Double]
    /// Massimo dell'asse; nil = il massimo dei valori (per la rete, che non ha un tetto).
    var upperBound: Double?
    /// Quanti punti occupa la larghezza intera.
    var slots = 60
    var secondary: [Double]? = nil
    var tint: Color = .accentColor
    /// Colore della seconda serie; nil = lo stesso della prima, più tenue e tratteggiato.
    var secondaryTint: Color? = nil

    var body: some View {
        Canvas { context, size in
            let top = max(upperBound ?? max(values.max() ?? 0, secondary?.max() ?? 0), 0.000_001)
            let main = points(values, top, size)
            if let first = main.first, let last = main.last {
                var area = Path()
                area.move(to: CGPoint(x: first.x, y: size.height))
                main.forEach { area.addLine(to: $0) }
                area.addLine(to: CGPoint(x: last.x, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(tint.opacity(0.16)))
                context.stroke(line(main), with: .color(tint),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            if let secondary {
                let other = line(points(secondary, top, size))
                if let secondaryTint {
                    context.stroke(other, with: .color(secondaryTint),
                                   style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                } else {
                    context.stroke(other, with: .color(tint.opacity(0.7)),
                                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2.5, 2]))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func points(_ data: [Double], _ top: Double, _ size: CGSize) -> [CGPoint] {
        let shown = data.suffix(slots)
        guard shown.count > 1 else { return [] }
        let step = size.width / CGFloat(max(1, slots - 1))
        let start = CGFloat(slots - shown.count) * step
        return shown.enumerated().map { i, v in
            let y = size.height - CGFloat(min(1, max(0, v / top))) * (size.height - 1.5) - 0.75
            return CGPoint(x: start + CGFloat(i) * step, y: y)
        }
    }

    private func line(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        pts.dropFirst().forEach { p.addLine(to: $0) }
        return p
    }
}

/// Quanto è pieno qualcosa (il disco), come una barra: semplice e senza letture continue.
struct FillBar: View {
    /// 0…1
    var fraction: Double
    var tint: Color

    var body: some View {
        Canvas { context, size in
            let h: CGFloat = 8
            let rect = CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
            context.fill(Path(roundedRect: rect, cornerRadius: h / 2), with: .style(.quaternary))
            var filled = rect
            filled.size.width = max(h, rect.width * CGFloat(min(1, max(0, fraction))))
            context.fill(Path(roundedRect: filled, cornerRadius: h / 2), with: .color(tint))
        }
        .accessibilityHidden(true)
    }
}
