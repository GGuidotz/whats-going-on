// Avvisi con soglie. Una regola scatta quando la condizione dura abbastanza, una volta sola: si riarma quando il valore
// torna sotto la soglia meno un margine (isteresi), e tra due avvisi uguali passa almeno un'attesa minima.
// Qui solo la logica: chi consegna l'avviso (isola di Cocaine o notifica) sta nell'app.

import Foundation

enum AlertKind: String, CaseIterable, Codable, Identifiable {
    case cpu, memory, disk, temperature, process
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: L("CPU alta")
        case .memory: L("Memoria sotto pressione")
        case .disk: L("Disco quasi pieno")
        case .temperature: L("Chip caldo")
        case .process: L("App che consuma troppo")
        }
    }
}

struct AlertRule: Codable, Equatable {
    var enabled: Bool
    /// CPU: % totale. Disco: % libero. Temperatura: gradi. App: % di un core. Memoria: ignorato (pressione critica).
    var threshold: Double
    /// Secondi di fila sopra soglia prima di avvisare.
    var duration: Double
}

struct AlertSettings: Codable, Equatable {
    var rules: [AlertKind: AlertRule] = [
        .cpu: AlertRule(enabled: true, threshold: 90, duration: 120),
        .memory: AlertRule(enabled: true, threshold: 0, duration: 30),
        .disk: AlertRule(enabled: true, threshold: 10, duration: 0),
        .temperature: AlertRule(enabled: true, threshold: 95, duration: 60),
        .process: AlertRule(enabled: true, threshold: 100, duration: 300),
    ]
    /// Minuti tra due avvisi dello stesso tipo.
    var cooldownMinutes: Double = 15

    subscript(kind: AlertKind) -> AlertRule {
        get { rules[kind] ?? AlertRule(enabled: false, threshold: 0, duration: 0) }
        set { rules[kind] = newValue }
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

    mutating func evaluate(_ s: Snapshot, settings: AlertSettings) -> [AlertEvent] {
        var events: [AlertEvent] = []
        for kind in AlertKind.allCases {
            let rule = settings[kind]
            guard rule.enabled else { states[kind] = nil; continue }
            guard let check = Self.check(kind, s, rule) else { continue }   // dato mancante: non cambiamo stato
            var state = states[kind] ?? State()

            if check.over {
                if state.since == nil { state.since = s.date }
                let held = s.date.timeIntervalSince(state.since ?? s.date)
                let cooled = state.lastFired.map { s.date.timeIntervalSince($0) >= settings.cooldownMinutes * 60 } ?? true
                if state.armed, held >= rule.duration, cooled {
                    events.append(AlertEvent(kind: kind, message: check.message))
                    state.armed = false
                    state.lastFired = s.date
                }
            } else {
                state.since = nil
                if check.rearm { state.armed = true }
            }
            states[kind] = state
        }
        return events
    }

    /// over: sopra soglia. rearm: abbastanza sotto da poter avvisare di nuovo.
    private static func check(_ kind: AlertKind, _ s: Snapshot, _ rule: AlertRule)
        -> (over: Bool, rearm: Bool, message: String)? {
        switch kind {
        case .cpu:
            guard let c = s.cpu else { return nil }
            let value = c.total * 100
            return (value >= rule.threshold, value < rule.threshold - 15,
                    L("CPU al %@ da %@", Format.percent(c.total), durationText(rule.duration)))
        case .memory:
            guard let m = s.memory else { return nil }
            let top = s.topByMemory.first.map { L(" (%@ usa %@)", $0.name, Format.bytes($0.memory)) } ?? ""
            return (m.pressure == .critical, m.pressure == .normal, L("Memoria sotto pressione") + top)
        case .disk:
            guard let d = s.disk else { return nil }
            let free = d.freeFraction * 100
            return (free < rule.threshold, free >= rule.threshold + 2,
                    L("Disco quasi pieno: %@ liberi", Format.diskBytes(d.free)))
        case .temperature:
            guard let t = s.sensors?.chip else { return nil }
            return (t >= rule.threshold, t < rule.threshold - 8,
                    L("Il chip è a %@ da %@", Format.celsius(t), durationText(rule.duration)))
        case .process:
            let top = s.topByCPU.first
            let value = top?.cpu ?? 0
            let name = top?.name ?? ""
            return (value >= rule.threshold, value < rule.threshold * 0.6,
                    L("%@ usa il %d%% della CPU da %@", name, Int(value.rounded()), durationText(rule.duration)))
        }
    }

    private static func durationText(_ seconds: Double) -> String {
        seconds >= 60 ? L("%d min", Int(seconds / 60)) : L("%d s", Int(seconds))
    }
}
