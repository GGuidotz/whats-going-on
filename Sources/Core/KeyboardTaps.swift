// Chi intercetta la tastiera. Un'app che vuole leggere o cambiare i tasti installa un "event tap" nel sistema:
// CGGetEventTapList (CoreGraphics, pubblica) li elenca tutti, con il processo, la modalità (attivo: può cambiare o
// bloccare i tasti, quindi ogni tasto lo aspetta; in ascolto: li vede soltanto), gli eventi che chiede e il ritardo
// misurato da macOS. Non serve alcun permesso: provato su macOS 27.2 senza Accesso completo al disco, Accessibilità
// o Monitoraggio dell'input. Non dice chi ha il permesso senza usarlo adesso (sta nel database TCC, protetto).
// Si legge solo a richiesta (scheda Tastiera, "Perché è lento?"): una chiamata al WindowServer.

import CoreGraphics
import Darwin
import Foundation

struct KeyboardTap: Equatable, Identifiable {
    var pid: Int32
    var name: String
    var path: String?
    /// Può cambiare o bloccare i tasti: ogni tasto aspetta la sua risposta.
    var active: Bool
    var enabled: Bool
    /// Ritardo medio misurato da macOS, in millisecondi; nil se non misurato o fuori scala.
    var latency: Double?
    var id: Int32 { pid }

    var isMacOS: Bool {
        guard let path else { return false }
        return SystemProcess.isMacOS(path: path)
    }

    /// Oltre questo ritardo un tap attivo si sente scrivendo.
    static let slowLatency = 50.0
    var isSlow: Bool { active && (latency ?? 0) >= Self.slowLatency }
}

enum KeyboardTapReader {
    /// Le app con almeno un tap sulla tastiera (tasti premuti e rilasciati, tasti modificatori), un elemento per app.
    /// nil se il sistema non risponde.
    static func read() -> [KeyboardTap]? {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return [] }
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        var filled: UInt32 = 0
        guard CGGetEventTapList(count, &taps, &filled) == .success else { return nil }

        let keys: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        var byPID: [Int32: KeyboardTap] = [:]
        for t in taps.prefix(Int(filled)) where t.eventsOfInterest & keys != 0 {
            let pid = t.tappingProcess
            let active = t.options == .defaultTap
            // Microsecondi. Oltre un secondo non è un ritardo credibile per un tasto (su macOS 27.2 compaiono valori di
            // secondi o minuti anche per tap di sistema): si tace invece di allarmare.
            let micro = Double(t.avgUsecLatency)
            let latency: Double? = micro > 0 && micro <= 1_000_000 ? micro / 1000 : nil
            var tap = byPID[pid] ?? {
                let n = name(pid)
                return KeyboardTap(pid: pid, name: n.name, path: n.path, active: false, enabled: false, latency: nil)
            }()
            tap.active = tap.active || active
            tap.enabled = tap.enabled || t.enabled
            if let latency { tap.latency = max(tap.latency ?? 0, latency) }
            byPID[pid] = tap
        }
        // Prima le app di terze parti attive, poi quelle in ascolto, poi macOS.
        return byPID.values.sorted {
            if $0.isMacOS != $1.isMacOS { return !$0.isMacOS }
            if $0.active != $1.active { return $0.active }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Il nome dell'app che contiene il processo ("Nexa Writer" per un suo aiutante), altrimenti il nome del processo.
    private static func name(_ pid: Int32) -> (name: String, path: String?) {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return ("pid \(pid)", nil) }
        let path = String(cString: buffer)
        if let range = path.range(of: ".app/"), let app = path[..<range.lowerBound].split(separator: "/").last {
            return (String(app), path)
        }
        return (path.split(separator: "/").last.map(String.init) ?? path, path)
    }
}

/// Che cosa dire delle app che intercettano la tastiera, in una riga.
struct KeyboardReport: Equatable {
    var taps: [KeyboardTap]

    /// Solo le app installate, non i servizi di macOS (Siri, accessibilità).
    var thirdParty: [KeyboardTap] { taps.filter { !$0.isMacOS && $0.enabled } }
    var activeThirdParty: [KeyboardTap] { thirdParty.filter(\.active) }
    var slow: [KeyboardTap] { thirdParty.filter(\.isSlow) }
}
