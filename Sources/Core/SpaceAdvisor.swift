// I consigli per liberare spazio, scritti da regole note e prudenti: si propone solo ciò che si ricrea da solo, ciò che
// è doppio (installer già usati) o ciò che non apri da tanto. L'ultima parola è tua: ogni consiglio mostra cosa
// toccherebbe, e "Sposta nel Cestino" non cancella nulla per sempre.

import Foundation

struct SpaceTip: Identifiable, Equatable {
    enum Action: Equatable {
        /// Gli elementi si possono spostare nel Cestino.
        case trash
        /// Si apre la cartella nel Finder (o un'app): la scelta va fatta lì.
        case reveal
        /// Solo un consiglio da leggere.
        case info
    }

    var id: String
    var symbol: String
    var title: String
    var detail: String
    var bytes: Int64
    var items: [FoundItem]
    var action: Action
}

enum SpaceAdvisor {
    static func tips(for result: DiskScanResult, home: String = NSHomeDirectory(), now: Date = Date()) -> [SpaceTip] {
        let tree = result.tree
        var tips: [SpaceTip] = []
        let monthsAgo = { (months: Double) in now.addingTimeInterval(-months * 30 * 86_400) }

        func size(_ path: String) -> Int64 { tree.find(path).map { tree[$0].size } ?? 0 }
        func children(_ path: String, atLeast minimum: Int64) -> [FoundItem] {
            guard let i = tree.find(path) else { return [] }
            return tree[i].children.compactMap { c in
                let node = tree[c]
                guard !node.isSynthetic, node.size >= minimum, let p = tree.path(of: c) else { return nil }
                return FoundItem(path: p, size: node.size, date: node.modified)
            }
        }

        // Cestino: si svuota dal Finder (cancellare per sempre è una scelta tua).
        let trash = size(home + "/.Trash")
        if trash >= 200_000_000 {
            tips.append(SpaceTip(id: "trash", symbol: "trash", title: L("Svuota il Cestino"),
                                 detail: L("Il Cestino tiene %@. Si svuota dal Finder: clic destro sul Cestino nel Dock.",
                                           Format.diskBytes(trash)),
                                 bytes: trash, items: [FoundItem(path: home + "/.Trash", size: trash, date: nil)],
                                 action: .reveal))
        }

        // Cache delle app: si ricreano da sole quando servono.
        let caches = children(home + "/Library/Caches", atLeast: 200_000_000)
        if !caches.isEmpty {
            let total = caches.reduce(0) { $0 + $1.size }
            tips.append(SpaceTip(id: "caches", symbol: "archivebox", title: L("Cache delle app"),
                                 detail: L("Le app le ricreano quando servono. Meglio chiudere l'app prima di toglierne la cache."),
                                 bytes: total, items: caches, action: .trash))
        }

        // Progetti fermi: dipendenze e prodotti di compilazione si ricostruiscono con un comando.
        let idle = result.findings.rebuildable.filter { ($0.date ?? .distantPast) < monthsAgo(1) }
        if !idle.isEmpty {
            tips.append(SpaceTip(id: "rebuildable", symbol: "hammer", title: L("Progetti fermi da più di un mese"),
                                 detail: L("node_modules, .build, DerivedData e simili: si ricostruiscono quando riapri il progetto (npm install, swift build, Xcode)."),
                                 bytes: idle.reduce(0) { $0 + $1.size }, items: idle, action: .trash))
        }

        // Xcode: supporto ai dispositivi e simulatori.
        let deviceSupport = ["iOS DeviceSupport", "watchOS DeviceSupport", "macOS DeviceSupport", "tvOS DeviceSupport",
                             "visionOS DeviceSupport"]
            .flatMap { children(home + "/Library/Developer/Xcode/" + $0, atLeast: 500_000_000) }
            .filter { ($0.date ?? .distantPast) < monthsAgo(3) }
        if !deviceSupport.isEmpty {
            tips.append(SpaceTip(id: "devicesupport", symbol: "iphone", title: L("Supporto dispositivi di Xcode"),
                                 detail: L("Simboli di versioni di iOS e watchOS che non colleghi da mesi. Xcode li riscarica se servono."),
                                 bytes: deviceSupport.reduce(0) { $0 + $1.size }, items: deviceSupport, action: .trash))
        }
        let simulators = size(home + "/Library/Developer/CoreSimulator")
        if simulators >= 5_000_000_000 {
            tips.append(SpaceTip(id: "simulators", symbol: "ipad.and.iphone", title: L("Simulatori di Xcode"),
                                 detail: L("%@ di simulatori. In Xcode › Window › Devices and Simulators togli quelli che non usi; dal Terminale: xcrun simctl delete unavailable.",
                                           Format.diskBytes(simulators)),
                                 bytes: simulators,
                                 items: [FoundItem(path: home + "/Library/Developer/CoreSimulator", size: simulators, date: nil)],
                                 action: .reveal))
        }

        // Installer: dopo l'installazione non servono più.
        let installers = result.findings.installers
        if !installers.isEmpty {
            tips.append(SpaceTip(id: "installers", symbol: "shippingbox", title: L("Installer già scaricati"),
                                 detail: L("DMG, PKG e simili: dopo l'installazione non servono più."),
                                 bytes: installers.reduce(0) { $0 + $1.size }, items: installers, action: .trash))
        }

        // Backup di iPhone e iPad sul Mac.
        let backups = children(home + "/Library/Application Support/MobileSync/Backup", atLeast: 1_000_000_000)
        if !backups.isEmpty {
            tips.append(SpaceTip(id: "backups", symbol: "externaldrive.badge.timemachine", title: L("Backup di iPhone e iPad"),
                                 detail: L("Backup locali. Se usi Backup di iCloud, quelli vecchi di solito non servono: controlla la data prima di toglierli."),
                                 bytes: backups.reduce(0) { $0 + $1.size }, items: backups, action: .trash))
        }
        let updates = size(home + "/Library/iTunes/iPhone Software Updates")
        if updates >= 1_000_000_000 {
            let path = home + "/Library/iTunes/iPhone Software Updates"
            tips.append(SpaceTip(id: "ipsw", symbol: "arrow.down.app", title: L("Aggiornamenti di iPhone scaricati"),
                                 detail: L("File di installazione di iOS già usati."),
                                 bytes: updates, items: [FoundItem(path: path, size: updates, date: nil)], action: .trash))
        }

        // File grandi che non apri da sei mesi.
        let old = result.findings.bigFiles.filter { ($0.date ?? .distantPast) < monthsAgo(6) }
            .filter { !installers.contains($0) }
        if !old.isEmpty {
            tips.append(SpaceTip(id: "bigfiles", symbol: "doc.badge.clock", title: L("File grandi non aperti da 6 mesi"),
                                 detail: L("Guardali uno per uno: se ti servono ancora, un disco esterno o iCloud Drive vanno bene."),
                                 bytes: old.reduce(0) { $0 + $1.size }, items: old, action: .trash))
        }

        // Da sistemare nelle app che li tengono.
        let messages = size(home + "/Library/Messages/Attachments")
        if messages >= 2_000_000_000 {
            tips.append(SpaceTip(id: "messages", symbol: "message", title: L("Allegati di Messaggi"),
                                 detail: L("%@ di foto e video ricevuti. In Messaggi › Impostazioni › Generali, \"Conserva i messaggi: 1 anno\" li sfoltisce da solo.",
                                           Format.diskBytes(messages)),
                                 bytes: messages, items: [], action: .info))
        }
        if let photos = largestPhotosLibrary(tree, home: home), photos.size >= 20_000_000_000 {
            tips.append(SpaceTip(id: "photos", symbol: "photo.on.rectangle", title: L("Libreria di Foto"),
                                 detail: L("%@. Con Foto di iCloud, in Foto › Impostazioni › iCloud scegli \"Ottimizza spazio su Mac\": gli originali restano in iCloud.",
                                           Format.diskBytes(photos.size)),
                                 bytes: photos.size, items: [], action: .info))
        }
        let docker = size(home + "/Library/Containers/com.docker.docker")
        if docker >= 10_000_000_000 {
            tips.append(SpaceTip(id: "docker", symbol: "shippingbox.circle", title: L("Docker"),
                                 detail: L("%@ di immagini e volumi. Dal Terminale: docker system prune, poi riduci il disco in Docker › Settings › Resources.",
                                           Format.diskBytes(docker)),
                                 bytes: docker, items: [], action: .info))
        }

        // Lo spazio che la lettura non vede.
        if let hidden = tree[tree.root].children.first(where: { tree[$0].isSynthetic && tree[$0].kind == .system }),
           tree[hidden].size >= 15_000_000_000 {
            tips.append(SpaceTip(id: "hidden", symbol: "eye.slash", title: L("Spazio non visibile"),
                                 detail: L("%@ tra file di sistema, snapshot locali di Time Machine e cartelle protette. macOS libera da solo gli snapshot quando serve spazio; con Accesso completo al disco la lettura ne vede di più.",
                                           Format.diskBytes(tree[hidden].size)),
                                 bytes: tree[hidden].size, items: [], action: .info))
        }

        return tips.sorted { $0.bytes > $1.bytes }
    }

    private static func largestPhotosLibrary(_ tree: DiskTree, home: String) -> FoundItem? {
        guard let pictures = tree.find(home + "/Pictures") else { return nil }
        return tree[pictures].children
            .filter { tree[$0].name.hasSuffix(".photoslibrary") }
            .compactMap { c in tree.path(of: c).map { FoundItem(path: $0, size: tree[c].size, date: nil) } }
            .max { $0.size < $1.size }
    }

    /// Un riassunto breve per Apple Intelligence: spazio, cartelle più grandi, consigli già trovati. Il modello sul
    /// dispositivo legge poche migliaia di parole, quindi solo l'essenziale. Nessun dato lascia il Mac.
    static func summary(_ result: DiskScanResult, tips: [SpaceTip], home: String = NSHomeDirectory()) -> String {
        let tree = result.tree
        var lines = [L("Disco: %@ in tutto, %@ usati.", Format.diskBytes(result.total), Format.diskBytes(result.used))]
        lines.append(L("Cartelle più grandi:"))
        var biggest: [(String, Int64)] = []
        var queue = [(tree.root, 0)]
        var next = 0
        while next < queue.count {
            let (i, depth) = queue[next]
            next += 1
            for c in tree[i].children where tree[c].isDirectory && !tree[c].isSynthetic {
                if let p = tree.path(of: c) { biggest.append((p, tree[c].size)) }
                if depth < 4 { queue.append((c, depth + 1)) }
            }
        }
        for (path, size) in biggest.sorted(by: { $0.1 > $1.1 }).prefix(18) {
            let shown = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
            lines.append("- \(shown): \(Format.diskBytes(size))")
        }
        if !tips.isEmpty {
            lines.append(L("Già proposti:"))
            for tip in tips.prefix(8) { lines.append("- \(tip.title): \(Format.diskBytes(tip.bytes))") }
        }
        return lines.joined(separator: "\n")
    }
}
