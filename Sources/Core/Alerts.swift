// Avvisi con soglie. Una regola scatta quando la condizione dura abbastanza, una volta sola: si riarma quando il valore
// torna sotto la soglia meno un margine (isteresi), e tra due avvisi uguali passa almeno un'attesa minima.
// Qui solo la logica: chi consegna l'avviso (isola di Cocaine o notifica) sta nell'app.
// Avvisano solo le cause gravi e transitorie. Elementi di avvio orfani, giorni di accensione e calore lieve restano
// nel pannello e nella frase: non sono urgenze.

import Foundation

enum AlertKind: String, CaseIterable, Codable, Identifiable {
    case cpu, memory, swap, disk, temperature, process, runaway
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: L("CPU alta")
        case .memory: L("Memoria sotto pressione")
        case .swap: L("Swap in crescita")
        case .disk: L("Disco quasi pieno")
        case .temperature: L("Chip caldo")
        case .process: L("App che consuma troppo")
        case .runaway: L("Processo fuori controllo")
        }
    }

    /// Il tipo conta da solo "da quanto" (processo fuori controllo: per PID, dalla lettura di ps): la durata della
    /// regola si confronta con la sua, non con quella del motore.
    var tracksOwnDuration: Bool { self == .runaway }
}

struct AlertRule: Codable, Equatable {
    var enabled: Bool
    /// CPU: % totale. Disco: % libero. Temperatura: gradi. App e processo: % di un core. Swap: MB in più in 30 minuti.
    /// Memoria: ignorato (pressione critica).
    var threshold: Double
    /// Secondi di fila sopra soglia prima di avvisare.
    var duration: Double
}

struct AlertSettings: Codable, Equatable {
    /// I predefiniti di un'installazione nuova: tutto acceso.
    static let defaultRules: [AlertKind: AlertRule] = [
        .cpu: AlertRule(enabled: true, threshold: 90, duration: 120),
        .memory: AlertRule(enabled: true, threshold: 0, duration: 30),
        .swap: AlertRule(enabled: true, threshold: 500, duration: 0),
        .disk: AlertRule(enabled: true, threshold: 15, duration: 0),
        .temperature: AlertRule(enabled: true, threshold: 95, duration: 60),
        .process: AlertRule(enabled: true, threshold: 100, duration: 300),
        .runaway: AlertRule(enabled: true, threshold: 90, duration: 600),
    ]
    /// Versione delle regole salvate: manca in quelle scritte prima della 0.7.0 (Preferences le aggiorna).
    static let currentSchema = 2

    var rules: [AlertKind: AlertRule] = Self.defaultRules
    /// Minuti tra due avvisi dello stesso tipo.
    var cooldownMinutes: Double = 15
    var schema: Int? = Self.currentSchema

    /// Un tipo che le regole salvate non conoscono (arrivato con un aggiornamento) resta spento, con le soglie
    /// predefinite: chi aggiorna lo accende se vuole, chi installa adesso lo trova acceso.
    subscript(kind: AlertKind) -> AlertRule {
        get {
            if let rule = rules[kind] { return rule }
            var rule = Self.defaultRules[kind] ?? AlertRule(enabled: false, threshold: 0, duration: 0)
            rule.enabled = false
            return rule
        }
        set { rules[kind] = newValue }
    }

    /// Le regole di una versione precedente: il disco passa dal vecchio predefinito (10%) al nuovo (15%), i tipi nuovi
    /// restano spenti (vedi il subscript).
    mutating func migrate() {
        guard (schema ?? 1) < Self.currentSchema else { return }
        if let disk = rules[.disk], disk.threshold == 10 { rules[.disk]?.threshold = 15 }
        for kind in AlertKind.allCases where rules[kind] == nil { rules[kind] = self[kind] }
        schema = Self.currentSchema
    }
}

struct AlertEvent: Equatable {
    var kind: AlertKind
    var message: String
}

struct AlertEngine {
    private struct State {
        var since: Date?
        var armed = true
        var lastFired: Date?
    }

    private var states: [AlertKind: State] = [:]
    /// PID per cui "processo fuori controllo" ha già avvisato: lo stesso processo non torna finché non si calma.
    private var runawayNotified: Set<Int32> = []

    mutating func evaluate(_ s: Snapshot, settings: AlertSettings) -> [AlertEvent] {
        var events: [AlertEvent] = []
        for kind in AlertKind.allCases {
            let rule = settings[kind]
            guard rule.enabled else { states[kind] = nil; continue }
            guard let check = check(kind, s, rule, settings) else { continue }   // dato mancante: non cambiamo stato
            var state = states[kind] ?? State()

            if check.over {
                if state.since == nil { state.since = s.date }
                let held = kind.tracksOwnDuration ? rule.duration : s.date.timeIntervalSince(state.since ?? s.date)
                let cooled = state.lastFired.map { s.date.timeIntervalSince($0) >= settings.cooldownMinutes * 60 } ?? true
                if state.armed, held >= rule.duration, cooled {
                    events.append(AlertEvent(kind: kind, message: check.message))
                    state.armed = false
                    state.lastFired = s.date
                    if kind == .runaway, let pid = check.pid { runawayNotified.insert(pid) }
                }
            } else {
                state.since = nil
                if check.rearm { state.armed = true }
            }
            states[kind] = state
        }
        return events
    }

    private struct Check {
        var over: Bool
        var rearm: Bool
        var message: String
        var pid: Int32? = nil
    }

    /// over: sopra soglia. rearm: abbastanza sotto da poter avvisare di nuovo.
    private mutating func check(_ kind: AlertKind, _ s: Snapshot, _ rule: AlertRule, _ settings: AlertSettings) -> Check? {
        let duration = Self.durationText(rule.duration)
        switch kind {
        case .cpu:
            guard let c = s.cpu else { return nil }
            let value = c.total * 100
            return Check(over: value >= rule.threshold, rearm: value < rule.threshold - 15,
                         message: L("CPU al %@ da %@", Format.percent(c.total), duration))
        case .memory:
            guard let m = s.memory else { return nil }
            let top = s.topByMemory.first.map { L(" (%@ usa %@)", $0.name, Format.bytes($0.memory)) } ?? ""
            return Check(over: m.pressure == .critical, rearm: m.pressure == .normal,
                         message: L("Memoria sotto pressione") + top)
        case .swap:
            // Quanto è cresciuto lo swap in 30 minuti: il Mac sta finendo la memoria e scrive sul disco.
            guard let m = s.memory, let change = s.swapTrend?.change30 else { return nil }
            let mb = Double(change) / 1_000_000
            let top = s.topByMemory.first(where: { $0.name != "kernel_task" })
                .map { L(" %@ usa %@.", $0.name, Format.bytes($0.memory)) } ?? ""
            return Check(over: mb >= rule.threshold, rearm: mb < rule.threshold / 2,
                         message: L("Lo swap è cresciuto di %@ in 30 minuti (ora %@): la memoria non basta.",
                                    Format.bytes(UInt64(max(0, change))), Format.bytes(m.swapUsed)) + top)
        case .disk:
            guard let d = s.disk else { return nil }
            let free = d.freeFraction * 100
            var message = L("Disco quasi pieno: %@ liberi", Format.diskBytes(d.free))
            if let f = s.diskForecast { message += " " + L("(pieno tra circa %@)", Format.days(f.daysLeft)) }
            return Check(over: free < rule.threshold, rearm: free >= rule.threshold + 2, message: message)
        case .temperature:
            guard let t = s.sensors?.chip else { return nil }
            return Check(over: t >= rule.threshold, rearm: t < rule.threshold - 8,
                         message: L("Il chip è a %@ da %@", Format.celsius(t), duration))
        case .process:
            // Con "processo fuori controllo" acceso, qui solo le app: i servizi li segue l'altro avviso, per PID.
            let apps = settings[.runaway].enabled ? s.topByCPU.filter { $0.bundlePath != nil } : s.topByCPU
            let top = apps.first
            let value = top?.cpu ?? 0
            return Check(over: value >= rule.threshold, rearm: value < rule.threshold * 0.6,
                         message: L("%@ usa il %d%% della CPU da %@", top?.name ?? "", Int(value.rounded()), duration))
        case .runaway:
            // Le app vere le segue "App che consuma troppo"; qui i processi di macOS e i servizi in background.
            let candidates = s.runaways.filter { $0.appName == nil }
            runawayNotified.formIntersection(candidates.map(\.pid))   // chi si è calmato può avvisare di nuovo
            let over = candidates.first {
                $0.cpu >= rule.threshold && s.date.timeIntervalSince($0.since) >= rule.duration
                    && !runawayNotified.contains($0.pid)
            }
            guard let p = over else {
                return Check(over: false, rearm: true, message: "")
            }
            let minutes = p.minutes(at: s.date)
            return Check(over: true, rearm: false,
                         message: L("%@ lavora al %d%% da %d min: è %@.", p.name, Int(p.cpu.rounded()), minutes, p.kind)
                            + " " + Diagnosis.hint(forProcess: p.name, isMacOS: p.isMacOS),
                         pid: p.pid)
        }
    }

    private static func durationText(_ seconds: Double) -> String {
        seconds >= 60 ? L("%d min", Int(seconds / 60)) : L("%d s", Int(seconds))
    }
}
