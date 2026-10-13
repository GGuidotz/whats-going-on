// I mattoni del pannello: riga di una misura (si apre con un clic), righe di dettaglio, barre dei core, elenco app.
// Ogni riga è una scheda del contenuto (riempimento standard, niente vetro); il colore del simbolo e del grafico segue
// la scala del carico, il valore resta scritto: il colore non è mai l'unico segnale.

import SwiftUI

struct MetricRow<Detail: View>: View {
    var symbol: String
    var title: String
    var value: String
    var caption: String?
    var values: [Double]
    var upperBound: Double?
    var secondary: [Double]? = nil
    var tint: Color = .accentColor
    var secondaryTint: Color? = nil
    /// Al posto del grafico, una barra di riempimento (0…1): per ciò che cambia piano, come il disco.
    var fill: Double? = nil
    var trend: String?
    @Binding var expanded: Bool
    @ViewBuilder var detail: () -> Detail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.body.weight(.medium))
                        .foregroundStyle(tint)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.subheadline).foregroundStyle(.secondary)
                        Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                        if let caption {
                            Text(caption).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 8)
                    Group {
                        if let fill {
                            FillBar(fraction: fill, tint: tint)
                        } else {
                            Sparkline(values: values, upperBound: upperBound, secondary: secondary, tint: tint,
                                      secondaryTint: secondaryTint)
                        }
                    }
                    .frame(width: 112, height: 30)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([title, value, caption, trend].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint(expanded ? L("Chiudi i dettagli") : L("Mostra i dettagli"))
            .accessibilityAddTraits(.isButton)

            if expanded {
                VStack(alignment: .leading, spacing: 4) { detail() }
                    .padding(.leading, 30)
                    .transition(.opacity)
            }
        }
        .contentCard(padding: 10)
    }
}

struct DetailLine: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

struct DetailHeading: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Una barra per core: a colpo d'occhio si vede se lavora un core solo o tutti.
struct CoreBars: View {
    var cores: [Double]

    var body: some View {
        // Un solo Canvas per tutti i core (anche 20): una vista invece di quaranta forme.
        Canvas { context, size in
            guard !cores.isEmpty else { return }
            let gap: CGFloat = 2
            let width = (size.width - gap * CGFloat(cores.count - 1)) / CGFloat(cores.count)
            for (i, v) in cores.enumerated() {
                let x = CGFloat(i) * (width + gap)
                context.fill(Path(roundedRect: CGRect(x: x, y: 0, width: width, height: size.height), cornerRadius: 1.5),
                             with: .style(.quaternary))
                let h = max(1.5, size.height * CGFloat(min(1, v)))
                context.fill(Path(roundedRect: CGRect(x: x, y: size.height - h, width: width, height: h), cornerRadius: 1.5),
                             with: .color(Palette.load(Severity.load(v))))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Carico per core"))
        .accessibilityValue(cores.enumerated().map { L("core %d: %@", $0.offset + 1, Format.percent($0.element)) }
            .joined(separator: ", "))
    }
}

struct ProcessList: View {
    enum Measure { case cpu, memory }
    var processes: [ProcessUsage]
    var measure: Measure

    var body: some View {
        ForEach(processes) { p in
            DetailLine(label: p.name, value: measure == .cpu ? Format.corePercent(p.cpu) : Format.bytes(p.memory))
        }
    }
}

extension MemoryPressure {
    var title: String {
        switch self {
        case .normal: L("Normale")
        case .warning: L("Alta")
        case .critical: L("Critica")
        }
    }
}

extension Summary.Level {
    var symbol: String {
        switch self {
        case .calm: "checkmark.circle.fill"
        case .busy: "gauge.with.dots.needle.67percent"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .calm: .green
        case .busy: .orange
        case .warning: .red
        }
    }
}

/// "in salita", "in discesa" o "stabile", confrontando gli ultimi secondi con quelli prima. Per VoiceOver.
func trendText(_ values: [Double]) -> String? {
    guard values.count >= 10 else { return nil }
    let recent = values.suffix(5).reduce(0, +) / 5
    let before = values.dropLast(5).suffix(5).reduce(0, +) / 5
    let scale = max(abs(before), 0.000_001)
    let change = (recent - before) / scale
    if change > 0.2 { return L("in salita") }
    if change < -0.2 { return L("in discesa") }
    return L("stabile")
}
