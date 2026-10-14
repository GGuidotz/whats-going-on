// Una frase su memoria e CPU, per l'attrezzo "App": cosa conviene fare adesso. Regole semplici, dette chiare: il primo
// gesto utile è quasi sempre chiudere l'app che pesa di più.

import Foundation

enum AppAdvisor {
    private static let browsers: Set<String> = ["Safari", "Google Chrome", "Firefox", "Arc", "Microsoft Edge", "Brave Browser",
                                                "Opera", "Vivaldi", "Orion", "Zen", "Dia"]

    static func memoryAdvice(_ s: Snapshot) -> String {
        guard let m = s.memory else { return L("Sto leggendo la memoria…") }
        let top = s.topByMemory.first(where: { $0.name != "kernel_task" })
        switch m.pressure {
        case .critical, .warning:
            guard let top else { return L("La memoria è sotto pressione: chiudi le app che non usi.") }
            if browsers.contains(top.name) {
                return L("La memoria è sotto pressione e %@ ne usa %@: chiudere i pannelli che non ti servono libera più di tutto.",
                         top.name, Format.bytes(top.memory))
            }
            return L("La memoria è sotto pressione: %@ ne usa %@. Chiuderla è la cosa che libera di più.",
                     top.name, Format.bytes(top.memory))
        case .normal:
            if m.swapUsed >= 4_000_000_000 {
                return L("Il Mac sta usando %@ di swap: chiudere un paio di app lo rende più svelto.", Format.bytes(m.swapUsed))
            }
            return L("La memoria va bene: macOS usa quella libera come cache, è normale vederla quasi piena.")
        }
    }

    static func cpuAdvice(_ s: Snapshot) -> String {
        guard let c = s.cpu else { return L("Sto leggendo la CPU…") }
        let top = s.topByCPU.first(where: { $0.name != "kernel_task" })
        if let top, top.cpu >= 80 {
            if ["mds_stores", "mds", "mdworker_shared", "photoanalysisd", "mediaanalysisd", "backupd"].contains(top.name) {
                return L("%@ è un lavoro di macOS (Spotlight, Foto o Time Machine): finisce da solo, meglio lasciarlo fare.",
                         top.name)
            }
            return L("%@ usa %@ della CPU: se non sta facendo qualcosa per te, chiuderla raffredda il Mac.",
                     top.name, Format.corePercent(top.cpu))
        }
        if c.total >= 0.8 { return L("La CPU lavora molto, divisa tra più app.") }
        return L("La CPU è tranquilla.")
    }

    /// Per Apple Intelligence: memoria, CPU e le app che pesano di più, in poche righe.
    static func summary(_ s: Snapshot) -> String {
        var lines: [String] = []
        if let m = s.memory {
            lines.append(L("Memoria: %@ usati di %@, pressione %@, swap %@.", Format.bytes(m.used), Format.bytes(m.total),
                           m.pressure.word, Format.bytes(m.swapUsed)))
        }
        if let c = s.cpu { lines.append(L("CPU: %@ in totale.", Format.percent(c.total))) }
        lines.append(L("App più pesanti (memoria, CPU):"))
        for p in s.topByMemory.prefix(8) {
            lines.append("- \(p.name): \(Format.bytes(p.memory)), \(Format.corePercent(p.cpu))")
        }
        for p in s.topByCPU.prefix(3) where !s.topByMemory.prefix(8).contains(p) {
            lines.append("- \(p.name): \(Format.bytes(p.memory)), \(Format.corePercent(p.cpu))")
        }
        return lines.joined(separator: "\n")
    }
}

extension MemoryPressure {
    /// Una parola per i testi: "normale", "alta", "critica".
    var word: String {
        switch self {
        case .normal: L("normale")
        case .warning: L("alta")
        case .critical: L("critica")
        }
    }
}
