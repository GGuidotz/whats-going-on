// La cronologia lunga nel pannello: 24 ore o 7 giorni di CPU, memoria e swap, spazio libero. Una scheda chiusa di
// predefinito (si ridisegna una volta al minuto, quando la cronologia aggiunge un punto). I buchi (Mac spento o in
// stop, app chiusa) restano buchi: la linea si interrompe invece di inventare valori.

import SwiftUI

/// Una linea nel tempo, con i buchi. Un solo Canvas.
struct TimelineChart: View {
    var values: [Double?]
    /// Massimo dell'asse; nil = il massimo dei valori.
    var upperBound: Double?
    var lowerBound: Double = 0
    var tint: Color

    var body: some View {
        Canvas { context, size in
            let present = values.compactMap { $0 }
            guard !present.isEmpty, values.count > 1 else { return }
            let top = max(upperBound ?? (present.max() ?? 1), lowerBound + 0.000_001)
            let step = size.width / CGFloat(values.count - 1)
            func y(_ v: Double) -> CGFloat {
                size.height - CGFloat(min(1, max(0, (v - lowerBound) / (top - lowerBound)))) * (size.height - 2) - 1
            }
            var line = Path(), area = Path()
            var segmentStart: CGPoint?
            var previous: CGPoint?
            func closeArea() {
                guard let start = segmentStart, let end = previous else { return }
                area.addLine(to: CGPoint(x: end.x, y: size.height))
                area.addLine(to: CGPoint(x: start.x, y: size.height))
                area.closeSubpath()
            }
            for (i, v) in values.enumerated() {
                guard let v else {
                    closeArea()
                    segmentStart = nil
                    previous = nil
                    continue
                }
                let p = CGPoint(x: CGFloat(i) * step, y: y(v))
                if previous == nil {
                    line.move(to: p)
                    area.move(to: p)
                    segmentStart = p
                    // un punto isolato si vede come un trattino
                    line.addLine(to: CGPoint(x: p.x + 1, y: p.y))
                } else {
                    line.addLine(to: p)
                    area.addLine(to: p)
                }
                previous = p
            }
            closeArea()
            context.fill(area, with: .color(tint.opacity(0.14)))
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct HistoryCard: View {
    enum Range: String, CaseIterable, Identifiable {
        case day, week
        var id: String { rawValue }
        var title: String { self == .day ? L("24 ore") : L("7 giorni") }
        var minutes: Int { self == .day ? 1440 : 7 * 1440 }
        /// Un punto ogni 5 minuti sulle 24 ore, ogni 30 sui 7 giorni: circa 300 punti per grafico.
        var step: Int { self == .day ? 5 : 30 }
    }

    var history: LongHistory
    var diskTotal: Int64?
    @State private var range: Range = .day
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Cronologia")).font(.subheadline).foregroundStyle(.secondary)
                        Text(coverage).font(.callout).monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Cronologia") + ", " + coverage)
            .accessibilityHint(expanded ? L("Chiudi i dettagli") : L("Mostra i dettagli"))
            .accessibilityAddTraits(.isButton)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(L("Periodo"), selection: $range) {
                        ForEach(Range.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    let now = Date()
                    chart(L("CPU, media"), values: series({ $0.cpu }, now), upper: 1,
                          tint: Palette.load(0.4), format: { Format.percent($0) })
                    chart(L("Memoria usata"), values: series({ $0.memory }, now), upper: 1,
                          tint: Palette.load(0.6), format: { Format.percent($0) })
                    chart(L("Swap"), values: series({ $0.swap }, now), upper: nil,
                          tint: Palette.upload, format: { Format.bytes(UInt64(max(0, $0))) })
                    chart(L("Spazio libero"), values: series({ $0.diskFree }, now), upper: diskTotal.map(Double.init),
                          tint: Palette.download, format: { Format.diskBytes(Int64($0)) })
                }
                .transition(.opacity)
            }
        }
        .contentCard(padding: 10)
    }

    private var coverage: String {
        guard let oldest = history.oldest else { return L("Si riempie un punto al minuto") }
        let hours = Date().timeIntervalSince(oldest) / 3600
        return hours >= 24 ? L("Ultimi %@", Format.days(min(7, hours / 24))) : L("Ultime %d ore", max(1, Int(hours)))
    }

    private func series(_ value: @escaping (HistoryPoint) -> Float, _ now: Date) -> [Double?] {
        history.series(value, minutes: range.minutes, step: range.step, now: now)
    }

    @ViewBuilder
    private func chart(_ title: String, values: [Double?], upper: Double?, tint: Color,
                       format: @escaping (Double) -> String) -> some View {
        let present = values.compactMap { $0 }
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let last = present.last, let low = present.min(), let high = present.max() {
                    Text(L("ora %@ · min %@ · max %@", format(last), format(low), format(high)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            TimelineChart(values: values, upperBound: upper, tint: tint)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.04)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(present.last.map { L("ora %@, minimo %@, massimo %@", format($0), format(present.min() ?? $0),
                                                 format(present.max() ?? $0)) } ?? L("nessun dato"))
    }
}
