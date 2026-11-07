// Cosa parte da solo: i LaunchAgents dell'utente (~/Library/LaunchAgents), quelli di tutti gli utenti
// (/Library/LaunchAgents) e i LaunchDaemons (/Library/LaunchDaemons). Si leggono senza permessi.
// Orfano = il programma che dovrebbe partire non c'è più, l'app a cui appartiene non è installata, oppure il file
// è vuoto. Capita quando un'app si toglie trascinandola nel Cestino: i suoi servizi restano e macOS prova ad avviarli.
// Azioni solo sugli agenti orfani dell'utente: disattivarli (launchctl, nel dominio dell'utente, senza password) o
// spostarne il file nel Cestino, sempre con conferma. Quelli in /Library chiedono la password di amministratore: qui
// si mostrano soltanto. Non si legge l'elenco "Elementi login" di Impostazioni di Sistema: serve l'amministratore.

import Foundation

struct StartupItem: Equatable, Identifiable {
    enum Domain: Int, CaseIterable, Comparable {
        case userAgent, globalAgent, daemon

        static func < (a: Domain, b: Domain) -> Bool { a.rawValue < b.rawValue }

        var folder: String {
            switch self {
            case .userAgent: NSHomeDirectory() + "/Library/LaunchAgents"
            case .globalAgent: "/Library/LaunchAgents"
            case .daemon: "/Library/LaunchDaemons"
            }
        }

        var title: String {
            switch self {
            case .userAgent: L("Agenti del tuo utente")
            case .globalAgent: L("Agenti di tutti gli utenti")
            case .daemon: L("Servizi di sistema")
            }
        }
    }

    enum Orphan: Equatable {
        /// Il programma non c'è più sul disco.
        case missingProgram(String)
        /// Nessuna delle app a cui dice di appartenere è installata.
        case missingApp(String)
        /// Il file non contiene niente da avviare.
        case empty

        var reason: String {
            switch self {
            case .missingProgram(let path): L("Il programma non c'è più: %@", (path as NSString).abbreviatingWithTildeInPath)
            case .missingApp(let id): L("L'app %@ non è installata", id)
            case .empty: L("Il file è vuoto: non avvia niente")
            }
        }
    }

    enum State: Equatable {
        case running(pid: Int32)
        /// Caricato ma fermo; il codice di uscita dell'ultima volta (diverso da 0: è finito con un errore).
        case loaded(lastExit: Int32)
        case notLoaded
        case unknown
    }

    var url: URL
    var domain: Domain
    var label: String
    var program: String?
    var bundleIDs: [String]
    var runAtLoad: Bool
    var keepAlive: Bool
    var orphan: Orphan?
    /// L'app che contiene il programma, se il percorso passa da un .app: "Nexa Updater".
    var appName: String?
    var disabled = false
    var state: State = .unknown
    var id: String { url.path }

    /// Si può disattivare o spostare nel Cestino da qui: solo gli agenti orfani dell'utente.
    var isActionable: Bool { domain == .userAgent && orphan != nil }

    /// Il nome da mostrare: l'app se c'è, altrimenti l'etichetta.
    var displayName: String { appName ?? label }
}

enum StartupScanner {
    /// Legge le tre cartelle. `appInstalled` dice se un'app con quell'identificativo c'è (NSWorkspace, dal lato app).
    static func scan(appInstalled: (String) -> Bool) -> [StartupItem] {
        let fm = FileManager.default
        var items: [StartupItem] = []
        for domain in StartupItem.Domain.allCases {
            guard let names = try? fm.contentsOfDirectory(atPath: domain.folder) else { continue }
            for name in names where name.hasSuffix(".plist") {
                let url = URL(fileURLWithPath: domain.folder).appendingPathComponent(name)
                items.append(item(url, domain: domain, appInstalled: appInstalled))
            }
        }
        return items.sorted {
            if $0.domain != $1.domain { return $0.domain < $1.domain }
            if ($0.orphan != nil) != ($1.orphan != nil) { return $0.orphan != nil }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    static func item(_ url: URL, domain: StartupItem.Domain, appInstalled: (String) -> Bool) -> StartupItem {
        let fallbackLabel = url.deletingPathExtension().lastPathComponent
        let plist = (try? Data(contentsOf: url))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
        let label = plist["Label"] as? String ?? fallbackLabel
        let arguments = plist["ProgramArguments"] as? [String] ?? []
        let program = (plist["Program"] as? String) ?? arguments.first
        let bundleIDs = plist["AssociatedBundleIdentifiers"] as? [String]
            ?? (plist["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []
        let keepAlive = (plist["KeepAlive"] as? Bool) ?? (plist["KeepAlive"] is [String: Any])

        var orphan: StartupItem.Orphan?
        let path = checkedPath(program: program, arguments: arguments)
        if program == nil && plist["BundleProgram"] == nil {
            orphan = .empty
        } else if let path, !FileManager.default.fileExists(atPath: path) {
            orphan = .missingProgram(path)
        } else if !bundleIDs.isEmpty, !(path?.contains(".app/") ?? false), !bundleIDs.contains(where: appInstalled) {
            // Un programma fuori da ogni app (/Library/PrivilegedHelperTools) resta anche quando l'app se ne va: conta
            // l'app a cui dice di appartenere. Se invece sta dentro un .app che esiste, l'app c'è (gli aggiornatori in
            // Application Support non sono registrati come app, ma ci sono).
            orphan = .missingApp(bundleIDs[0])
        }

        var appName: String?
        if let program, let range = program.range(of: ".app/") {
            // L'app più esterna: "Nexa.app/Contents/Library/LaunchAgents/Nexa Helper.app" → Nexa
            let outer = program[..<range.lowerBound]
            appName = outer.split(separator: "/").last.map(String.init)
        }
        return StartupItem(url: url, domain: domain, label: label, program: program, bundleIDs: bundleIDs,
                           runAtLoad: plist["RunAtLoad"] as? Bool ?? false, keepAlive: keepAlive, orphan: orphan,
                           appName: appName, disabled: plist["Disabled"] as? Bool ?? false)
    }

    /// Il percorso da controllare: il programma, se è assoluto; per "open -a /Applications/X.app" l'app aperta.
    private static func checkedPath(program: String?, arguments: [String]) -> String? {
        guard let program else { return nil }
        let expanded = (program as NSString).expandingTildeInPath
        if expanded.hasSuffix("/open") || expanded == "open" {
            return arguments.dropFirst().map { ($0 as NSString).expandingTildeInPath }
                .first { $0.hasPrefix("/") && ($0.hasSuffix(".app") || $0.contains(".app/")) }
        }
        return expanded.hasPrefix("/") ? expanded : nil
    }

    // MARK: - Stato (launchctl, dominio dell'utente)

    /// Aggiunge in esecuzione / fermo / disattivato agli agenti (anche quelli di /Library/LaunchAgents girano nel
    /// dominio dell'utente). I servizi di sistema restano "sconosciuto": launchctl li mostra solo all'amministratore.
    static func withState(_ items: [StartupItem]) -> [StartupItem] {
        let uid = getuid()
        let list = run(["list"]) ?? ""
        var loaded: [String: StartupItem.State] = [:]
        for line in list.split(separator: "\n").dropFirst() {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count >= 3 else { continue }
            let label = String(f[2])
            if let pid = Int32(f[0]) {
                loaded[label] = .running(pid: pid)
            } else {
                loaded[label] = .loaded(lastExit: Int32(f[1]) ?? 0)
            }
        }
        let disabled = disabledLabels(run(["print-disabled", "gui/\(uid)"]) ?? "")
        return items.map { item in
            var item = item
            guard item.domain != .daemon else { return item }
            item.state = loaded[item.label] ?? .notLoaded
            if disabled.contains(item.label) { item.disabled = true }
            return item
        }
    }

    /// Le righe di `launchctl print-disabled`: "com.nexa.agent" => disabled (o true, nelle versioni più vecchie).
    static func disabledLabels(_ text: String) -> Set<String> {
        var out = Set<String>()
        for line in text.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value == "disabled" || value == "true" else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            out.insert(label)
        }
        return out
    }

    // MARK: - Azioni (solo agenti orfani dell'utente)

    enum ActionError: Error, Equatable {
        case notAllowed
        case failed(String)
    }

    /// Lo ferma e lo disattiva: non ripartirà, nemmeno al prossimo accesso. Il file resta dov'è.
    static func disable(_ item: StartupItem) throws {
        guard item.isActionable else { throw ActionError.notAllowed }
        let target = "gui/\(getuid())/\(item.label)"
        _ = run(["bootout", target])   // se non era caricato, launchctl si lamenta: va bene così
        guard run(["disable", target]) != nil else { throw ActionError.failed("launchctl disable") }
    }

    /// Lo riattiva: ripartirà al prossimo accesso.
    static func enable(_ item: StartupItem) throws {
        guard item.domain == .userAgent else { throw ActionError.notAllowed }
        guard run(["enable", "gui/\(getuid())/\(item.label)"]) != nil else { throw ActionError.failed("launchctl enable") }
    }

    /// Lo ferma e sposta il file nel Cestino (si può rimettere a posto dal Cestino).
    static func moveToTrash(_ item: StartupItem) throws {
        guard item.isActionable else { throw ActionError.notAllowed }
        _ = run(["bootout", "gui/\(getuid())/\(item.label)"])
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        } catch {
            throw ActionError.failed(error.localizedDescription)
        }
    }

    /// launchctl con questi argomenti: l'uscita, o nil se è finito con un errore.
    @discardableResult
    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// In breve: quanti sono e quanti orfani.
struct StartupReport: Equatable {
    var total: Int
    var orphans: Int
    var userOrphans: Int

    init(_ items: [StartupItem]) {
        total = items.count
        orphans = items.filter { $0.orphan != nil }.count
        userOrphans = items.filter(\.isActionable).count
    }
}
