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

    /// Per Apple Intelligence: memoria, CPU e le app che pesano di più, con una nota su cosa sono.
    static func summary(_ s: Snapshot) -> String {
        var lines: [String] = []
        if let m = s.memory {
            lines.append(L("Memoria: %@ usati di %@, pressione %@, swap %@.", Format.bytes(m.used), Format.bytes(m.total),
                           m.pressure.word, Format.bytes(m.swapUsed)))
            lines.append(m.pressure == .normal
                ? L("Con pressione normale la memoria piena non è un problema: macOS usa quella libera come cache.")
                : L("La pressione alta vuol dire che il Mac sta comprimendo memoria o usando lo swap: rallenta."))
        }
        if let c = s.cpu { lines.append(L("CPU: %@ in totale (100%% = tutti i core).", Format.percent(c.total))) }
        lines.append(L("App più pesanti (memoria, CPU dove 100% = un core, nota):"))
        var listed = Set<String>()
        for p in s.topByMemory.prefix(8) + s.topByCPU.prefix(4) where !listed.contains(p.name) {
            listed.insert(p.name)
            var line = "- \(p.name): \(Format.bytes(p.memory)), \(Format.corePercent(p.cpu))"
            if let note = hint(for: p.name) { line += ". " + note }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Cos'è un processo noto e cosa si può fare, in una frase. nil se non lo sappiamo.
    static func hint(for name: String) -> String? {
        if browsers.contains(name) || name.hasSuffix("Helper (Renderer)") || name.hasPrefix("Google Chrome Helper") {
            return L("browser: ogni pannello aperto pesa, chiudere quelli inutili libera di più")
        }
        switch name {
        case "kernel_task": return L("il sistema: sale quando il Mac è caldo per rallentare la CPU, non si chiude")
        case "WindowServer": return L("disegna lo schermo: pesa di più con molti monitor, finestre e trasparenze")
        case "mds", "mds_stores", "mdworker", "mdworker_shared":
            return L("Spotlight che indicizza: finisce da solo, si può escludere una cartella in Impostazioni › Spotlight")
        case "photoanalysisd", "mediaanalysisd": return L("Foto che analizza la libreria: finisce da solo, meglio con il Mac in carica")
        case "backupd": return L("Time Machine che fa un backup: finisce da solo")
        case "com.apple.Virtualization.VirtualMachine", "qemu-system-aarch64", "UTM", "Parallels Desktop", "VMware Fusion",
             "Docker", "com.docker.backend", "OrbStack":
            return L("macchina virtuale o Docker: tiene la memoria che le hai assegnato, si riduce dalle sue impostazioni")
        case "Xcode", "Simulator", "SourceKitService", "swift-frontend":
            return L("Xcode: i simulatori aperti e l'indicizzazione pesano, chiudi i simulatori che non usi")
        case "Slack", "Microsoft Teams", "Discord", "Code", "Cursor", "Notion", "Spotify", "WhatsApp", "Claude", "ChatGPT":
            return L("app costruita su un browser (Electron): pesa anche quando non la usi, chiudila se non ti serve")
        case "Microsoft Outlook", "Microsoft Word", "Microsoft Excel", "Microsoft PowerPoint":
            return L("Microsoft Office: con documenti grandi o tanta posta occupa molta memoria")
        default: return nil
        }
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
