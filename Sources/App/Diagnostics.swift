// Diagnostica: un registro breve di ciò che succede (avvisi, aggiornamenti) e un report in testo semplice da allegare
// a una segnalazione. Solo in memoria, mai dati personali: niente nomi di file, niente indirizzi, niente app aperte.

import AppKit
import Foundation

enum DiagCategory: String {
    case app, alerts, update, feedback
}

@MainActor
final class DiagnosticsLog: ObservableObject {
    static let shared = DiagnosticsLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let category: DiagCategory
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    func add(_ category: DiagCategory, _ message: String) {
        entries.append(Entry(date: Date(), category: category, message: message))
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
    }

    nonisolated static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}

/// Scorciatoia per scrivere nel registro da qualsiasi punto del codice sul main actor.
@MainActor
func diag(_ category: DiagCategory, _ message: String) {
    DiagnosticsLog.shared.add(category, message)
}

enum SystemInfo {
    /// "Mac14,2"
    static var model: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static var macOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    static var version: String { info["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { info["CFBundleVersion"] as? String ?? "?" }
    static var commit: String { info["WGOGitCommit"] as? String ?? "?" }

    /// Una riga per le email e le segnalazioni: "What's Going On 0.4.0 (12) · macOS 27.0.1 · Mac14,2 · it".
    static var oneLine: String {
        "What's Going On \(version) (\(build)) · macOS \(macOS) · \(model) · \(Localization.effectiveCode)"
    }
}

enum DiagnosticsReport {
    @MainActor
    static func make(model: AppModel) -> String {
        var out: [String] = []
        func section(_ title: String) { out.append(""); out.append("## \(title)") }
        func row(_ key: String, _ value: String) { out.append("- \(key): \(value)") }
        func yesNo(_ b: Bool) -> String { b ? "yes" : "no" }

        let s = model.monitor.snapshot, prefs = model.prefs
        out.append("# What's Going On diagnostics")
        row("Generated", DiagnosticsLog.stamp(Date()))

        section("App")
        row("Version", "\(SystemInfo.version) (build \(SystemInfo.build), commit \(SystemInfo.commit))")
        row("Icon", SystemInfo.info["WGOIconTier"] as? String ?? "?")
        row("Installed via", Updater.channel == .homebrew ? "Homebrew" : "source build")
        row("Language", "\(prefs.language.rawValue) → \(Localization.effectiveCode)")

        section("Mac")
        row("Model", SystemInfo.model)
        row("macOS", "\(SystemInfo.macOS) (\(ProcessInfo.processInfo.operatingSystemVersionString))")
        row("Architecture", SystemInfo.architecture)
        row("Cores", "\(s.cpu?.perCore.count ?? 0)")
        row("Memory", s.memory.map { Format.bytes($0.total) } ?? "?")

        section("Readings available")
        row("CPU", yesNo(s.cpu != nil))
        row("Memory", yesNo(s.memory != nil))
        row("Network", yesNo(s.network != nil))
        row("Disk", yesNo(s.disk != nil))
        row("Battery", yesNo(s.battery != nil))
        row("Chip temperature", yesNo(s.sensors?.chip != nil))
        row("Temperature sensors listed", "\(s.sensors?.all.count ?? 0) (all only in advanced mode, panel open)")
        row("System power (SMC)", yesNo(s.sensors?.systemWatts != nil))
        row("GPU", s.gpu != nil ? "yes" : (model.monitor.needs.gpu ? "no" : "not requested"))
        row("Summary", model.monitor.summary.title)

        section("Preferences")
        row("Menu bar", prefs.visibleModules.map(\.rawValue).joined(separator: ", ") + " (\(prefs.style.rawValue))")
        row("Interval", "\(prefs.interval) s, temperature every \(Int(prefs.temperatureInterval)) s with panel closed")
        if let own = s.ownUsage {
            row("This app now", "\(Format.corePercent(own.cpu)) CPU, \(Format.bytes(own.memory))")
        }
        row("Away (screens off or locked)", yesNo(model.monitor.isAway))
        row("Advanced", yesNo(prefs.advanced))
        row("Alerts to", prefs.alertDestination.rawValue)
        row("Alert rules", AlertKind.allCases.map { k in
            let r = prefs.alerts[k]
            return "\(k.rawValue) \(r.enabled ? "on" : "off") \(Int(r.threshold))/\(Int(r.duration))s"
        }.joined(separator: "; "))
        row("Automatic update check", yesNo(prefs.autoCheckUpdates))

        section("Cocaine")
        let c = CocaineAlertSettings.read()
        row("Installed", yesNo(model.delivery.cocaineInstalled))
        row("Running", yesNo(model.delivery.cocaineRunning))
        row("Also at the Mac", yesNo(c.whenPresent))
        row("Flash", yesNo(c.flash))
        row("Paused", c.pausedUntil.map { "until " + DiagnosticsLog.stamp($0) } ?? "no")
        row("Idle now", "\(Int(AlertDelivery.idleSeconds)) s")

        section("Updates")
        row("State", "\(model.updater.state)")
        row("Last check", model.updater.lastCheck.map(DiagnosticsLog.stamp) ?? "never")

        section("Log")
        let entries = DiagnosticsLog.shared.entries.suffix(60)
        if entries.isEmpty { out.append("(empty)") }
        for e in entries { out.append("\(DiagnosticsLog.stamp(e.date)) [\(e.category.rawValue)] \(e.message)") }
        return out.joined(separator: "\n") + "\n"
    }

    static var suggestedFileName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "WhatsGoingOn-diagnostics-\(f.string(from: Date())).txt"
    }
}
