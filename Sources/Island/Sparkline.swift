// Il grafico degli ultimi istanti: una linea con un'area leggera sotto. Scorre da destra, come il tempo.
// Lo leggono gli occhi, non VoiceOver: il valore e la tendenza li porta l'etichetta della riga.

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
        GeometryReader { geo in
            let top = max(upperBound ?? max(values.max() ?? 0, secondary?.max() ?? 0), 0.000_001)
            ZStack {
                area(values, top, geo.size).fill(tint.opacity(0.16))
                line(values, top, geo.size).stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let secondary {
                    if let secondaryTint {
                        line(secondary, top, geo.size)
                            .stroke(secondaryTint, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                    } else {
                        line(secondary, top, geo.size)
                            .stroke(tint.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2.5, 2]))
                    }
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

    private func line(_ data: [Double], _ top: Double, _ size: CGSize) -> Path {
        Path { p in
            let pts = points(data, top, size)
            guard let first = pts.first else { return }
            p.move(to: first)
            pts.dropFirst().forEach { p.addLine(to: $0) }
        }
    }

    private func area(_ data: [Double], _ top: Double, _ size: CGSize) -> Path {
        Path { p in
            let pts = points(data, top, size)
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: size.height))
            pts.forEach { p.addLine(to: $0) }
            p.addLine(to: CGPoint(x: last.x, y: size.height))
            p.closeSubpath()
        }
    }
}
