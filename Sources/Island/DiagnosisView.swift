// La risposta a "Perché è lento?": le cause dalla più grave, ognuna con la prova e cosa fare. Il simbolo e la parola
// della gravità dicono la stessa cosa del colore (il colore non è mai l'unico segnale).

import SwiftUI

struct DiagnosisView: View {
    var diagnosis: Diagnosis
    /// Apre l'attrezzo giusto per una causa; nil = niente pulsanti (chi ospita la pagina non ha attrezzi).
    var openTool: ((Cause.Tool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if diagnosis.causes.isEmpty {
                Label {
                    Text(L("Non trovo cause evidenti: memoria, swap, CPU, disco e calore sono a posto. Se il Mac sembra lento, può essere un'app sola: guardala mentre succede."))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.callout)
            }
            ForEach(diagnosis.causes) { cause in
                CauseRow(cause: cause, openTool: openTool)
            }
            Text(L("Letto alle %@, con regole fisse: la stessa situazione dà sempre la stessa risposta.",
                   diagnosis.date.formatted(date: .omitted, time: .shortened)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct CauseRow: View {
    var cause: Cause
    var openTool: ((Cause.Tool) -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: cause.severity.symbol)
                .foregroundStyle(cause.severity.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(cause.title)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(cause.evidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Text(cause.advice)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if let tool = cause.tool, let openTool {
                    Button(tool.title) { openTool(tool) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([cause.severity.title, cause.title, cause.evidence, cause.advice].joined(separator: ". "))
    }
}

extension Cause.Severity {
    var symbol: String {
        switch self {
        case .serious: "exclamationmark.triangle.fill"
        case .notice: "exclamationmark.circle"
        case .info: "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .serious: .red
        case .notice: .orange
        case .info: .secondary
        }
    }

    var title: String {
        switch self {
        case .serious: L("Rallenta adesso")
        case .notice: L("Può rallentare")
        case .info: L("Da sapere")
        }
    }
}

extension Cause.Tool {
    var title: String {
        switch self {
        case .space: L("Apri Attrezzi › Spazio")
        case .memory, .cpu: L("Apri Attrezzi › App")
        case .startup: L("Apri Attrezzi › Avvio")
        case .keyboard: L("Apri Attrezzi › Tastiera")
        }
    }
}
