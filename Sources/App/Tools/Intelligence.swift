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
            prompt = L("Dati del disco di questo Mac:\n%@\n\nScrivi 4 consigli per liberare spazio, dal più utile (tanto spazio, poco rischio). Ogni consiglio nomina una voce precisa dei dati con la sua dimensione, dice come ridurla (con quale app o impostazione, seguendo la nota della voce) e quanto spazio libera al massimo. Niente consigli generici o già mostrati, niente file di sistema, indice di Spotlight o memoria virtuale. Un consiglio per riga, ogni riga inizia con \"- \".", context)
        case .apps:
            prompt = L("Memoria e CPU di questo Mac adesso:\n%@\n\nScrivi 3 consigli per renderlo più svelto adesso, dal più utile. Ogni consiglio nomina un'app precisa dei dati con quanto pesa e dice cosa fare (seguendo la nota dell'app). Se la memoria va bene e la CPU è tranquilla, dillo in un consiglio e non inventare problemi. Niente consigli generici come riavviare il Mac. Un consiglio per riga, ogni riga inizia con \"- \".", context)
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
                    You are an expert Mac technician. You read a short report about one Mac and give specific advice \
                    for that Mac only: every tip names an item from the report, its size, the concrete action and \
                    the app or setting to use. Use the notes in the report: they say what each item is and how it \
                    is safely reduced. Never invent items, sizes or settings that are not in the report. Never \
                    suggest deleting system files, the Spotlight index or virtual memory. Each tip is one sentence \
                    under 40 words, written in the language of the request.
                    Example of a good tip: "- ~/Downloads (6,4 GB): open it in the Finder sorted by size and move \
                    the videos you have already watched to an external disk; frees up to 6,4 GB."
                    """)
                let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.3))
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
