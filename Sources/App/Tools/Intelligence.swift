// Consigli di Apple Intelligence (sperimentale, da Impostazioni › Generale). Il modello è quello sul Mac
// (FoundationModels, macOS 26): niente rete, niente dati che escono. Gli si passa un riassunto breve (il modello legge
// poche migliaia di parole) e si chiedono da 3 a 5 consigli, uno per riga. Gira solo quando premi il pulsante.
// Con un SDK senza FoundationModels, o prima di macOS 26, la funzione semplicemente non c'è.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AdviceModel: ObservableObject {
    enum Topic { case space, apps }

    enum State: Equatable {
        case idle
        case working
        case answer([String])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    /// nil se Apple Intelligence si può usare adesso, altrimenti perché no.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return L("Questo Mac non supporta Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return L("Apple Intelligence è spenta: Impostazioni di Sistema › Apple Intelligence e Siri.")
            case .unavailable(.modelNotReady):
                return L("Il modello di Apple Intelligence si sta ancora scaricando.")
            default:
                return L("Apple Intelligence non è disponibile adesso.")
            }
        }
        #endif
        return L("Serve macOS 26 con Apple Intelligence.")
    }

    func ask(_ topic: Topic, context: String) {
        task?.cancel()
        let prompt: String
        switch topic {
        case .space:
            prompt = L("Ecco lo stato del disco di un Mac:\n%@\n\nDai da 3 a 5 consigli pratici e sicuri per liberare spazio, adatti proprio a questi dati. Un consiglio per riga, ogni riga inizia con \"- \". Non proporre di cancellare file di sistema. Rispondi in italiano.", context)
        case .apps:
            prompt = L("Ecco memoria e CPU di un Mac adesso:\n%@\n\nDai da 3 a 5 consigli pratici per renderlo più svelto, adatti proprio a questi dati. Un consiglio per riga, ogni riga inizia con \"- \". Rispondi in italiano.", context)
        }
        state = .working
        task = Task { [weak self] in
            let result = await Self.respond(prompt)
            guard !Task.isCancelled else { return }
            self?.state = result
        }
    }

    func reset() {
        task?.cancel()
        state = .idle
    }

    private static func respond(_ prompt: String) async -> State {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: """
                    You are a careful macOS assistant. You give short, practical and safe advice about disk space, \
                    memory and CPU on a Mac, based only on the data you are given. Never suggest deleting system \
                    files or running commands that delete data without asking. Keep each tip under 35 words.
                    """)
                let response = try await session.respond(to: prompt)
                return .answer(parse(response.content))
            } catch {
                diag(.app, "apple intelligence failed: \(error)")
                return .failed(L("Apple Intelligence non ha risposto: %@", error.localizedDescription))
            }
        }
        #endif
        return .failed(unavailableReason ?? L("Apple Intelligence non è disponibile adesso."))
    }

    /// Le righe che iniziano con un trattino, un punto elenco o un numero; se non ce ne sono, il testo intero.
    private static func parse(_ text: String) -> [String] {
        let tips = text.components(separatedBy: .newlines).compactMap { raw -> String? in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard let first = line.first else { return nil }
            if first == "-" || first == "•" || first == "*" {
                line.removeFirst()
            } else if first.isNumber, let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }),
                      line.distance(from: line.startIndex, to: dot) <= 2 {
                line = String(line[line.index(after: dot)...])
            } else {
                return nil
            }
            line = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
            return line.isEmpty ? nil : line
        }
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return tips.isEmpty ? (whole.isEmpty ? [] : [whole]) : tips
    }
}
