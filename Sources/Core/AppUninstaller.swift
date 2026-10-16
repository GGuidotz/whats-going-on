// Disinstallare un'app per davvero: l'app e ciò che lascia nella Libreria (dati, cache, preferenze, contenitori,
// stato salvato, agenti di avvio). Solo regole note e prudenti:
// - si cerca per identificativo del bundle (com.azienda.app), che è quasi sempre univoco: questi avanzi sono proposti
//   già scelti;
// - si cerca nelle cartelle dei produttori (Application Support/Google/Chrome): il produttore viene dall'identificativo
//   (com.google.Chrome) e dentro si prende solo la cartella con il nome esatto dell'app, così Google Drive o le altre
//   app dello stesso produttore restano dove sono;
// - si cerca anche per nome della cartella uguale al nome dell'app, solo in Application Support, Caches e Logs: può
//   essere di un'altra app dello stesso produttore, quindi si propone ma non è scelto;
// - ciò che sta fuori dalla tua cartella utente (/Library) si mostra soltanto: per toglierlo serve la password, dal Finder.
// Le app di Apple e What's Going On stessa non si disinstallano da qui. Tutto va nel Cestino, mai cancellato.

import Foundation

struct InstalledApp: Identifiable, Equatable {
    var path: String
    var name: String
    /// Il nome nel bundle, se è diverso da quello del file ("Code" per "Visual Studio Code").
    var bundleName: String? = nil
    var bundleID: String?
    var version: String?
    /// Spazio allocato del bundle; nil finché non è stato misurato.
    var size: Int64?
    /// L'ultima volta che l'hai aperta, per Spotlight; nil se non lo sa.
    var lastUsed: Date?
    var id: String { path }

    var isApple: Bool { bundleID?.hasPrefix("com.apple.") ?? false }
    /// Dentro /Applications o ~/Applications, non nelle app di sistema.
    var isRemovable: Bool { !isApple && bundleID != Bundle.main.bundleIdentifier }
}

struct Leftover: Identifiable, Equatable {
    enum Match: Equatable {
        /// Il nome contiene l'identificativo dell'app: è suo.
        case bundleID
        /// Nella cartella del produttore, con il nome esatto dell'app (Google/Chrome): è sua.
        case vendor
        /// Una cartella con lo stesso nome dell'app: probabile, da guardare.
        case name
    }

    var path: String
    var size: Int64
    var match: Match
    /// Fuori dalla cartella utente: si toglie dal Finder, con la password.
    var needsAdmin: Bool
    var id: String { path }
    var name: String {
        let last = (path as NSString).lastPathComponent
        guard match == .vendor else { return last }
        return ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent + "/" + last
    }

    /// Dove sta, in parole: "Application Support", "Preferenze"…
    var place: String {
        var folder = (path as NSString).deletingLastPathComponent
        if match == .vendor { folder = (folder as NSString).deletingLastPathComponent }
        let parent = (folder as NSString).lastPathComponent
        switch parent {
        case "Preferences": return L("Preferenze")
        case "Caches": return L("Cache")
        case "Containers", "Group Containers": return L("Contenitore")
        case "Saved Application State": return L("Stato delle finestre")
        case "LaunchAgents", "LaunchDaemons": return L("Avvio automatico")
        case "Logs": return L("Log")
        case "Cookies", "HTTPStorages", "WebKit": return L("Dati web")
        case "PrivilegedHelperTools": return L("Aiutante di sistema")
        default: return parent
        }
    }
}

enum AppUninstaller {
    /// Le cartelle delle app: /Applications (anche un livello sotto, per Utility e le cartelle dei produttori) e
    /// ~/Applications.
    static func roots(home: String = NSHomeDirectory()) -> [String] {
        ["/Applications", home + "/Applications"]
    }

    /// Le app installate, senza dimensioni (si misurano dopo, una per una). Veloce: legge solo gli Info.plist.
    static func list(home: String = NSHomeDirectory()) -> [InstalledApp] {
        let fm = FileManager.default
        var paths: [String] = []
        for root in roots(home: home) {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                let path = root + "/" + entry
                if entry.hasSuffix(".app") {
                    paths.append(path)
                } else if let inner = try? fm.contentsOfDirectory(atPath: path) {
                    paths += inner.filter { $0.hasSuffix(".app") }.map { path + "/" + $0 }
                }
            }
        }
        return paths.compactMap(app(at:)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func app(at path: String) -> InstalledApp? {
        let plist = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any]
        let fallback = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        // Il nome del file è quello che vedi nel Finder; quello del bundle serve a trovare gli avanzi.
        let inner = (plist?["CFBundleName"] as? String) ?? (plist?["CFBundleDisplayName"] as? String)
        var app = InstalledApp(path: path, name: fallback,
                               bundleID: plist?["CFBundleIdentifier"] as? String,
                               version: plist?["CFBundleShortVersionString"] as? String)
        if let inner, !inner.isEmpty, inner != fallback { app.bundleName = inner }
        app.lastUsed = NSMetadataItem(url: URL(fileURLWithPath: path))?
            .value(forAttribute: "kMDItemLastUsedDate") as? Date
        return app
    }

    /// Spazio allocato da una cartella, file per file. Si interrompe se `cancelled` diventa vero.
    static func allocatedSize(_ path: String, cancelled: () -> Bool = { false }) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return Int64((try? url.resourceValues(forKeys: Set(keys)))?.totalFileAllocatedSize ?? 0)
        }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                                          errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        var count = 0
        for case let file as URL in walker {
            count += 1
            if count % 2000 == 0, cancelled() { return total }
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Gli avanzi di un'app nella Libreria, dal più grande.
    /// - others: gli identificativi delle altre app installate. Servono a non prendere per avanzi di Chrome
    ///   (com.google.Chrome) i dati di Chrome Canary (com.google.Chrome.canary).
    static func leftovers(for app: InstalledApp, others: Set<String> = [], home: String = NSHomeDirectory()) -> [Leftover] {
        let fm = FileManager.default
        var found: [String: (Leftover.Match, Bool)] = [:]

        func entries(_ dir: String) -> [String] { (try? fm.contentsOfDirectory(atPath: dir)) ?? [] }
        func add(_ path: String, _ match: Leftover.Match, admin: Bool) {
            guard fm.fileExists(atPath: path), path != app.path else { return }
            if let existing = found[path], existing.0 != .name { return }
            found[path] = (match, admin)
        }

        if let id = app.bundleID, id.count >= 5, id.contains("."), !app.isApple {
            let lower = id.lowercased()
            // Il nome è l'identificativo, o comincia con l'identificativo seguito da un punto.
            let longer = others.map { $0.lowercased() }.filter { $0 != lower && $0.hasPrefix(lower + ".") }
            func owns(_ entry: String) -> Bool {
                let e = entry.lowercased()
                guard e == lower || e.hasPrefix(lower + ".") else { return false }
                return !longer.contains { e == $0 || e.hasPrefix($0 + ".") }
            }
            for base in [home + "/Library", "/Library"] {
                let admin = base == "/Library"
                for folder in ["Application Support", "Caches", "Logs", "Containers", "HTTPStorages", "WebKit",
                               "Application Scripts", "Saved Application State", "Preferences", "Cookies",
                               "LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools", "Preferences/ByHost"] {
                    let dir = base + "/" + folder
                    for entry in entries(dir) where owns(entry) {
                        add(dir + "/" + entry, .bundleID, admin: admin)
                    }
                }
                // Gruppi condivisi: "TEAMID.com.azienda.app" o "group.com.azienda.app".
                for entry in entries(base + "/Group Containers") where entry.lowercased().hasSuffix("." + lower) {
                    add(base + "/Group Containers/" + entry, .bundleID, admin: admin)
                }
            }
        }

        // Nella cartella del produttore: com.google.Chrome → Google/Chrome, e "Google Chrome" → Google/Chrome.
        if !app.isApple {
            var vendors = Set<String>()
            if let id = app.bundleID {
                let parts = id.split(separator: ".")
                if parts.count >= 3, parts[1].count >= 3 { vendors.insert(parts[1].lowercased()) }
            }
            let words = app.name.split(separator: " ")
            if words.count >= 2, words[0].count >= 3 { vendors.insert(words[0].lowercased()) }
            var names = Set([app.name, app.bundleName].compactMap { $0?.lowercased() })
            if words.count >= 2 { names.insert(words.dropFirst().joined(separator: " ").lowercased()) }
            names = names.filter { $0.count >= 3 && !genericNames.contains($0) && !vendors.contains($0) }
            for base in [home + "/Library", "/Library"] where !vendors.isEmpty && !names.isEmpty {
                for folder in ["Application Support", "Caches", "Logs"] {
                    let dir = base + "/" + folder
                    for vendor in entries(dir) where vendors.contains(vendor.lowercased()) {
                        for entry in entries(dir + "/" + vendor) where names.contains(entry.lowercased()) {
                            add(dir + "/" + vendor + "/" + entry, .vendor, admin: base == "/Library")
                        }
                    }
                }
            }
        }

        // Per nome, solo dove le app lo usano e solo se il nome non è troppo generico.
        for name in [app.name, app.bundleName].compactMap({ $0 })
        where name.count >= 4 && !genericNames.contains(name.lowercased()) && !app.isApple {
            for base in [home + "/Library", "/Library"] {
                for folder in ["Application Support", "Caches", "Logs"] {
                    let path = base + "/" + folder + "/" + name
                    if found[path] == nil { add(path, .name, admin: base == "/Library") }
                }
            }
        }

        return found.map { path, value in
            Leftover(path: path, size: allocatedSize(path), match: value.0, needsAdmin: value.1)
        }
        .sorted { $0.size > $1.size }
    }

    /// Nomi di cartelle che appartengono a molte app o al sistema: non si propongono mai per nome.
    private static let genericNames: Set<String> = [
        "google", "microsoft", "adobe", "apple", "mozilla", "default", "crashreporter", "temp", "cache", "logs",
        "data", "support", "update", "updater", "helper", "plugins", "shared", "common", "user", "users", "system",
    ]
}
