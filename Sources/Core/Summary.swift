// La frase in cima al pannello: risponde a "che succede?" con la cosa più importante adesso, in parole.
// È l'elemento per cui l'app si ricorda. Una sola osservazione principale, al massimo una secondaria.

import Foundation

struct Summary: Equatable {
    enum Level: Int, Comparable {
        case calm, busy, warning
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    var title: String
    var detail: String?
    var level: Level

    static let starting = Summary(title: L("Sto guardando…"), detail: nil, level: .calm)
}

/// Tiene la memoria di "da quanto" (un'app che lavora da 4 minuti dice di più di un picco di un secondo).
struct SummaryEngine {
    private var hotSince: [String: Date] = [:]

    /// Percento di un core oltre il quale un'app "lavora molto".
    static let hotProcess = 80.0

    mutating func update(_ s: Snapshot) -> Summary {
        let now = s.date
        struct Note { var level: Summary.Level; var weight: Double; var text: String }
        var notes: [Note] = []

        if let m = s.memory {
            switch m.pressure {
            case .critical:
                if let top = s.topByMemory.first {
                    notes.append(Note(level: .warning, weight: 100, text: L("Memoria sotto pressione: %@ usa %@", top.name, Format.bytes(top.memory))))
                } else {
                    notes.append(Note(level: .warning, weight: 100, text: L("Memoria sotto pressione")))
                }
            case .warning:
                notes.append(Note(level: .busy, weight: 40, text: L("La memoria comincia a scarseggiare")))
            case .normal:
                break
            }
        }

        if let d = s.disk, d.freeFraction < 0.1 {
            notes.append(Note(level: .warning, weight: 90, text: L("Disco quasi pieno: %@ liberi", Format.diskBytes(d.free))))
        }

        if let b = s.battery, !b.onAC, b.level <= 0.1 {
            notes.append(Note(level: .warning, weight: 85, text: L("Batteria al %d%%", Int((b.level * 100).rounded()))))
        }

        if let t = s.sensors?.chip, t >= 95 {
            notes.append(Note(level: .warning, weight: 80, text: L("Il chip è molto caldo: %@", Format.celsius(t))))
        }

        // App che lavorano molto, con la durata.
        let hot = s.processes.filter { $0.cpu >= Self.hotProcess }
        hotSince = hotSince.filter { name, _ in hot.contains { $0.name == name } }
        for p in hot where hotSince[p.name] == nil { hotSince[p.name] = now }
        if let top = hot.max(by: { $0.cpu < $1.cpu }) {
            let minutes = Int(now.timeIntervalSince(hotSince[top.name] ?? now) / 60)
            let text = minutes >= 1
                ? L("%@ usa il %d%% della CPU da %d min", top.name, Int(top.cpu.rounded()), minutes)
                : L("%@ usa il %d%% della CPU", top.name, Int(top.cpu.rounded()))
            notes.append(Note(level: .busy, weight: 60 + Double(min(minutes, 30)), text: text))
        }

        if let c = s.cpu {
            if c.total >= 0.85 {
                notes.append(Note(level: .busy, weight: 55, text: L("La CPU è quasi al massimo (%@)", Format.percent(c.total))))
            }
        }

        if let n = s.network {
            if n.download >= 5_000_000 {
                notes.append(Note(level: .busy, weight: 30, text: L("Stai scaricando a %@", Format.rate(n.download))))
            }
            if n.upload >= 2_000_000 {
                notes.append(Note(level: .busy, weight: 29, text: L("Stai caricando a %@", Format.rate(n.upload))))
            }
        }

        if let d = s.disk, d.readRate + d.writeRate >= 200_000_000 {
            notes.append(Note(level: .busy, weight: 20, text: L("Il disco lavora molto (%@)", Format.rate(d.readRate + d.writeRate))))
        }

        notes.sort { $0.weight > $1.weight }
        guard let first = notes.first else {
            // Tutto tranquillo: la seconda riga dice comunque chi lavora di più, se qualcuno lavora.
            var detail: String?
            if let top = s.topByCPU.first, top.cpu >= 5 {
                detail = L("L'app più attiva è %@ (%@)", top.name, Format.corePercent(top.cpu))
            }
            return Summary(title: L("Tutto tranquillo"), detail: detail, level: .calm)
        }
        return Summary(title: first.text, detail: notes.dropFirst().first?.text, level: first.level)
    }
}
