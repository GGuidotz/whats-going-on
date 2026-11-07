// "Perché è lento?": le cause possibili adesso, ognuna con la prova (i numeri) e cosa fare. Solo regole fisse, scritte
// qui: la stessa situazione dà sempre la stessa risposta. Apple Intelligence, se c'è e se la chiedi, può riscriverle
// in modo discorsivo (Sources/App/Tools/Intelligence.swift), ma non aggiunge cause.
// Le soglie sono prudenti: su un Mac da 8 GB la memoria piena è normale, conta lo swap che cresce.

import Foundation

struct Cause: Equatable, Identifiable {
    enum Severity: Int, Comparable {
        /// Da sapere, non rallenta adesso.
        case info
        /// Può rallentare.
        case notice
        /// Rallenta adesso.
        case serious

        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    /// Dove si sistema, se l'app ha un attrezzo per farlo.
    enum Tool: Equatable { case space, memory, cpu, startup, keyboard }

    var id: String
    var severity: Severity
    var title: String
    var evidence: String
    var advice: String
    var tool: Tool?
    /// Per ordinare a parità di gravità.
    var weight: Double = 0
}

struct Diagnosis: Equatable {
    var date: Date
    var causes: [Cause]

    /// Il testo per Apple Intelligence: una causa per riga, con prova e consiglio.
    var plainText: String {
        causes.map { "- \($0.title). \($0.evidence) \($0.advice)" }.joined(separator: "\n")
    }

    /// Le soglie, in un posto solo (le usa anche la frase in cima al pannello).
    static let swapGrowth30: Int64 = 300_000_000
    static let swapGrowth60: Int64 = 500_000_000
    static let diskLow = 0.15
    static let diskCritical = 0.10
    static let runawayCPU = 80.0
    static let longUptime: TimeInterval = 14 * 86_400

    static func make(_ s: Snapshot, keyboard: KeyboardReport? = nil, startup: StartupReport? = nil) -> Diagnosis {
        var causes: [Cause] = []
        let now = s.date

        // Memoria e swap.
        if let m = s.memory {
            let trend = s.swapTrend
            let growing = (trend?.change30 ?? 0) >= swapGrowth30 || (trend?.change60 ?? 0) >= swapGrowth60
            let compressedShare = m.total > 0 ? Double(m.compressed) / Double(m.total) : 0
            var severity: Cause.Severity?
            if m.pressure == .critical || growing {
                severity = .serious
            } else if m.pressure == .warning || compressedShare >= 0.25 || m.swapUsed >= 1_000_000_000 {
                severity = .notice
            }
            if let severity {
                var evidence = L("RAM da %@: app %@, riservata %@, compressa %@; swap %@.",
                                 Format.bytes(m.total), Format.bytes(m.app), Format.bytes(m.wired),
                                 Format.bytes(m.compressed), Format.bytes(m.swapUsed))
                if let change = trend?.change30, change != 0 {
                    evidence += " " + L("Swap negli ultimi 30 minuti: %@.", Format.signedBytes(change))
                } else if let change = trend?.change60, change != 0 {
                    evidence += " " + L("Swap nell'ultima ora: %@.", Format.signedBytes(change))
                }
                let top = s.topByMemory.filter { $0.name != "kernel_task" && $0.name != "What's Going On" }.prefix(3)
                var advice = top.isEmpty
                    ? L("Chiudi le app che non usi.")
                    : L("Chiudi quelle che non usi tra le più pesanti: %@. Il peso di ogni app comprende la sua parte compressa.",
                        top.map { L("%@ (%@)", $0.name, Format.bytes($0.memory)) }.joined(separator: ", "))
                if let up = s.uptime, up >= 7 * 86_400, m.swapUsed >= 1_000_000_000 {
                    advice += " " + L("Un riavvio svuota lo swap.")
                }
                causes.append(Cause(id: "memory", severity: severity,
                                    title: severity == .serious ? L("La memoria non basta: il Mac scrive sul disco")
                                                                : L("La memoria è al limite"),
                                    evidence: evidence, advice: advice, tool: .memory, weight: 100))
            }
        }

        // Processi che lavorano molto da un po', anche di sistema.
        for p in s.runaways where p.cpu >= runawayCPU && p.minutes(at: now) >= 2 {
            let minutes = p.minutes(at: now)
            causes.append(Cause(id: "runaway.\(p.pid)", severity: minutes >= 10 ? .serious : .notice,
                                title: L("%@ lavora al %d%% da %d min", p.name, Int(p.cpu.rounded()), minutes),
                                evidence: L("È %@ (PID %d).", p.kind, Int(p.pid)),
                                advice: hint(forProcess: p.name, isMacOS: p.isMacOS),
                                tool: p.isMacOS ? nil : (p.appName != nil ? .cpu : .startup),
                                weight: 80 + p.cpu / 10))
        }

        // Spotlight.
        if let sp = s.spotlight, sp.minutes(at: now) >= 2 {
            causes.append(Cause(id: "spotlight", severity: .notice,
                                title: L("Spotlight sta indicizzando da %d min", sp.minutes(at: now)),
                                evidence: L("I suoi processi usano il %d%% di un core.", Int(sp.cpu.rounded())),
                                advice: L("Rallenta disco e CPU per un po' e finisce da solo: succede dopo un aggiornamento di macOS o dopo aver copiato molti file."),
                                weight: 50))
        }

        // Disco.
        if let d = s.disk, d.freeFraction < diskLow {
            var evidence = L("%@ liberi su %@.", Format.diskBytes(d.free), Format.diskBytes(d.total))
            if let f = s.diskForecast {
                evidence += " " + L("Al ritmo degli ultimi giorni (%@ al giorno) è pieno tra circa %@.",
                                    Format.diskBytes(Int64(f.bytesPerDay)), Format.days(f.daysLeft))
            }
            causes.append(Cause(id: "disk", severity: d.freeFraction < diskCritical ? .serious : .notice,
                                title: L("Disco quasi pieno: %@ libero", Format.percent(d.freeFraction)),
                                evidence: evidence,
                                advice: L("Con meno del 15% libero macOS fatica a gestire swap, aggiornamenti e cache. Attrezzi › Spazio mostra cosa occupa di più."),
                                tool: .space, weight: 90))
        }

        // Calore.
        switch s.thermal {
        case .serious, .critical:
            var evidence = L("Stato termico di macOS: %@.", s.thermal.title)
            if let t = s.sensors?.chip { evidence += " " + L("Chip a %@.", Format.celsius(t)) }
            causes.append(Cause(id: "thermal", severity: .serious, title: L("macOS sta rallentando il Mac per il calore"),
                                evidence: evidence,
                                advice: L("Lascia libere le prese d'aria e chiudi le app che lavorano di più. Un kernel_task alto è l'effetto del calore, non la causa."),
                                tool: .cpu, weight: 85))
        case .fair:
            causes.append(Cause(id: "thermal", severity: .info, title: L("Il Mac è tiepido"),
                                evidence: L("Stato termico di macOS: %@.", s.thermal.title),
                                advice: L("Niente di grave: macOS non limita ancora le prestazioni."), weight: 10))
        case .nominal:
            break
        }

        // CPU piena, divisa tra tante app (le singole le dice già "processo che lavora da molto").
        if let c = s.cpu, c.total >= 0.85, !causes.contains(where: { $0.id.hasPrefix("runaway.") }) {
            let top = s.topByCPU.prefix(3).map { L("%@ (%@)", $0.name, Format.corePercent($0.cpu)) }
            causes.append(Cause(id: "cpu", severity: .notice,
                                title: L("La CPU è quasi al massimo (%@)", Format.percent(c.total)),
                                evidence: top.isEmpty ? L("Il lavoro è diviso tra molti processi.")
                                                      : L("Lavorano di più: %@.", top.joined(separator: ", ")),
                                advice: L("Attrezzi › App mostra chi lavora: chiudi ciò che non serve adesso."),
                                tool: .cpu, weight: 60))
        }

        // Tastiera: ogni tap attivo è un passaggio in più per ogni tasto.
        if let k = keyboard, !k.thirdParty.isEmpty {
            let active = k.activeThirdParty
            var evidence = L("Intercettano la tastiera: %@.", k.thirdParty.map(\.name).joined(separator: ", "))
            for tap in k.slow {
                evidence += " " + L("Ritardo di %@: %@ ms.", tap.name, Format.number(tap.latency ?? 0, digits: 0))
            }
            causes.append(Cause(id: "keyboard",
                                severity: (active.count >= 2 || !k.slow.isEmpty) ? .notice : .info,
                                title: L("%d app intercettano la tastiera, %d in modo attivo", k.thirdParty.count, active.count),
                                evidence: evidence,
                                advice: L("Ogni tasto passa da ognuna di quelle attive: se scrivere è lento, chiudi quelle che non usi."),
                                tool: .keyboard, weight: 40))
        }

        // Da quanto è acceso.
        if let up = s.uptime, up >= longUptime {
            let swap = s.memory?.swapUsed ?? 0
            causes.append(Cause(id: "uptime", severity: .info, title: L("Acceso da %@", Format.days(up / 86_400)),
                                evidence: swap >= 1_000_000_000 ? L("Nel frattempo lo swap è arrivato a %@.", Format.bytes(swap))
                                                                : L("Molto tempo senza un riavvio."),
                                advice: L("Un riavvio svuota swap e memoria compressa e chiude i processi rimasti appesi."),
                                weight: 20))
        }

        // Elementi di avvio orfani.
        let orphans = startup?.orphans ?? s.startupOrphans ?? 0
        if orphans > 0 {
            causes.append(Cause(id: "startup", severity: .info,
                                title: orphans == 1 ? L("1 elemento di avvio orfano") : L("%d elementi di avvio orfani", orphans),
                                evidence: L("Servizi di app che non ci sono più: macOS prova ancora ad avviarli."),
                                advice: L("Attrezzi › Avvio li elenca; quelli del tuo utente si disattivano o si spostano nel Cestino da lì."),
                                tool: .startup, weight: 15))
        }

        causes.sort { $0.severity != $1.severity ? $0.severity > $1.severity : $0.weight > $1.weight }
        return Diagnosis(date: now, causes: causes)
    }

    /// Che cosa fa un processo che lavora molto, e se conviene preoccuparsi.
    static func hint(forProcess name: String, isMacOS: Bool) -> String {
        switch name {
        case "mds", "mds_stores", "mdworker", "mdworker_shared", "corespotlightd":
            return L("È Spotlight che indicizza: finisce da solo.")
        case "mediaanalysisd", "photoanalysisd":
            return L("È Foto che analizza la libreria: lavora soprattutto a Mac inattivo, poi si ferma.")
        case "assistant_service", "assistantd", "siriactionsd", "siriknowledged":
            return L("È un servizio di Siri e della dettatura: se resta così per ore, un riavvio lo sistema senza perdere dati.")
        case "backupd":
            return L("È Time Machine: finisce da solo.")
        case "softwareupdated":
            return L("macOS sta scaricando o preparando un aggiornamento.")
        case "bird", "cloudd", "fileproviderd":
            return L("È iCloud che sincronizza: finisce da solo.")
        case "kernel_task":
            return L("macOS rallenta il chip per raffreddarlo: è l'effetto del calore, non la causa.")
        case "WindowServer":
            return L("Disegna lo schermo: sale con molte finestre, schermi esterni o animazioni.")
        default:
            return isMacOS
                ? L("È un processo di macOS: di solito finisce da solo. Se dura ore, un riavvio lo ferma senza perdere dati.")
                : L("È un servizio in background di un'altra app: se non ti serve, Attrezzi › Avvio mostra cosa parte da solo.")
        }
    }
}
