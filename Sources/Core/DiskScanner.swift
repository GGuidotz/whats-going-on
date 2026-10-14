// La mappa dello spazio: legge tutto il disco una volta, solo quando lo chiedi, e ne fa un albero leggero.
//
// Come GrandPerspective, ma senza tenere in memoria ogni file: cartelle e file sotto una soglia (circa 1 MB, o
// 1/200000 dello spazio usato sui dischi molto pieni) finiscono sommati in un solo elemento "Altri n elementi". Così
// anche un disco con milioni di file resta qualche decina di migliaia di nodi.
//
// Lettura con getattrlistbulk: una chiamata restituisce nome, tipo, date e spazio allocato di decine di voci, senza
// uno stat per file (è il modo più veloce su APFS). Niente link simbolici, i collegamenti fisici contati una volta. Si parte da "/" e si resta sui due volumi del disco di avvio (sistema e dati): i firmlink di APFS
// (/Users, /Applications…) portano già ai dati, quindi /System (con /System/Volumes) e i dischi esterni in /Volumes
// restano fuori.
// Lo spazio che la lettura non vede (snapshot di Time Machine, volumi di sistema, cartelle protette) diventa un
// elemento a parte, "Non visibile", perché i conti tornino con lo spazio usato.
//
// Durante la lettura si annotano anche le cose che di solito si possono togliere: cartelle rigenerabili dei progetti
// (node_modules, .build…), installer nei Download, file molto grandi. I consigli li scrive SpaceAdvisor.

import Darwin
import Foundation

enum FileKind: Int, CaseIterable, Identifiable {
    case apps, documents, media, development, system, caches, other
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .apps: L("App e installer")
        case .documents: L("Documenti")
        case .media: L("Foto, video e musica")
        case .development: L("Sviluppo")
        case .system: L("Sistema")
        case .caches: L("Cache e log")
        case .other: L("Altro")
        }
    }
}

struct DiskNode {
    var name: String
    /// Byte allocati, figli compresi.
    var size: Int64
    var kind: FileKind
    var isDirectory: Bool
    /// "Altri n elementi" o "Non visibile": non è un percorso vero.
    var isSynthetic = false
    /// File e cartelle contenuti (per le cartelle), 1 per i file.
    var items: Int
    var modified: Date?
    /// Figli, dal più grande.
    var children: [Int] = []
    var parent: Int = -1
}

/// Qualcosa trovato durante la lettura: percorso, dimensione e data utile (ultimo uso o ultima modifica).
struct FoundItem: Identifiable, Equatable {
    var path: String
    var size: Int64
    var date: Date?
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

struct ScanFindings {
    /// Cartelle che si ricostruiscono da sole (node_modules, .build, DerivedData…), con l'ultima attività del progetto.
    var rebuildable: [FoundItem] = []
    /// DMG, PKG, XIP e ISO nella cartella utente.
    var installers: [FoundItem] = []
    /// File da almeno 1 GB nella cartella utente, con l'ultimo uso.
    var bigFiles: [FoundItem] = []
    /// Cartelle che non si sono potute aprire.
    var unreadable = 0
}

struct ScanProgress: Equatable {
    var items = 0
    var bytes: Int64 = 0
    var current = ""
}

/// Cosa è successo durante la lettura, per la sezione Debug degli Attrezzi.
struct ScanStats {
    var directories = 0
    var files = 0
    var closed = 0
    var unreadable = 0
    var errors = 0
    var skipped = 0
    var otherDevice = 0
    var hardLinks = 0
    /// Le prime cartelle che non si sono potute aprire, con l'errore.
    var unreadableSamples: [String] = []
    var devices: [Int32] = []
    var minKeep: Int64 = 0
    var nodes = 0
    var cancelled = false
    /// Perché la lettura non ha dato un risultato (nil se l'ha dato o se l'hai interrotta tu).
    var failure: String?
}

struct DiskTree {
    var nodes: [DiskNode]
    var root: Int
    /// Il percorso da cui è partita la lettura ("/").
    var rootPath: String

    subscript(_ i: Int) -> DiskNode { nodes[i] }

    /// Il percorso vero di un nodo (nil per gli elementi sommati).
    func path(of index: Int) -> String? {
        guard nodes.indices.contains(index), !nodes[index].isSynthetic else { return nil }
        var parts: [String] = []
        var i = index
        while i != root, i >= 0 {
            parts.append(nodes[i].name)
            i = nodes[i].parent
        }
        let tail = parts.reversed().joined(separator: "/")
        if tail.isEmpty { return rootPath }
        return rootPath.hasSuffix("/") ? rootPath + tail : rootPath + "/" + tail
    }

    /// Il nodo di un percorso, se la lettura lo ha tenuto (le cose piccole sono sommate).
    func find(_ path: String) -> Int? {
        guard path.hasPrefix(rootPath) else { return nil }
        var rest = String(path.dropFirst(rootPath.count))
        if rest.hasPrefix("/") { rest.removeFirst() }
        var current = root
        for part in rest.split(separator: "/") where !part.isEmpty {
            guard let next = nodes[current].children.first(where: { nodes[$0].name == part && !nodes[$0].isSynthetic })
            else { return nil }
            current = next
        }
        return current
    }

    /// Ancora nell'albero: risalendo si arriva alla radice (ciò che è finito nel Cestino ne resta staccato).
    func isAttached(_ index: Int) -> Bool {
        var i = index
        var steps = 0
        while i != root {
            guard nodes.indices.contains(i), steps < 512 else { return false }
            i = nodes[i].parent
            steps += 1
        }
        return true
    }

    /// Dalla radice al nodo, per la barra del percorso.
    func ancestry(of index: Int) -> [Int] {
        var chain: [Int] = []
        var i = index
        while i >= 0 {
            chain.append(i)
            if i == root { break }
            i = nodes[i].parent
        }
        return chain.reversed()
    }

    /// Toglie un percorso dall'albero dopo che è finito nel Cestino: la sua dimensione esce da tutti gli antenati.
    /// Se il percorso era sommato in "Altri elementi", si toglie dalla cartella più vicina che c'è.
    mutating func remove(_ path: String, size: Int64) {
        if let i = find(path), i != root {
            let removed = nodes[i].size
            let parent = nodes[i].parent
            if parent >= 0 { nodes[parent].children.removeAll { $0 == i } }
            subtract(removed, from: parent)
            nodes[i].parent = -1
            return
        }
        var probe = (path as NSString).deletingLastPathComponent
        while !probe.isEmpty, probe != "/" {
            if let i = find(probe) {
                subtract(size, from: i)
                return
            }
            probe = (probe as NSString).deletingLastPathComponent
        }
        subtract(size, from: root)
    }

    private mutating func subtract(_ bytes: Int64, from index: Int) {
        var i = index
        while i >= 0 {
            nodes[i].size = max(0, nodes[i].size - bytes)
            if i == root { break }
            i = nodes[i].parent
        }
    }
}

struct DiskScanResult {
    var tree: DiskTree
    var findings: ScanFindings
    /// Spazio usato secondo il volume, al momento della lettura.
    var used: Int64
    var total: Int64
    var duration: TimeInterval
}

/// La lettura. Va chiamata su una coda in background; `cancel()` si può chiamare da qualunque thread.
final class DiskScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    /// Si legge a lettura finita, sullo stesso thread che ha ricevuto il risultato.
    private(set) var stats = ScanStats()

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Una cartella aperta durante la lettura.
    private final class Frame {
        let name: String
        let path: String
        let level: Int
        let context: FileKind?
        let rebuildable: Bool
        let insideRebuildable: Bool
        /// Dentro la cartella utente: solo lì si annotano installer e file grandi.
        let inHome: Bool
        let modified: Date?
        var size: Int64 = 0
        var items = 0
        var kinds = [Int64](repeating: 0, count: FileKind.allCases.count)
        var kept: [Int] = []
        var smallSize: Int64 = 0
        var smallItems = 0
        /// Ultima modifica dei file qui sotto (fuori dalle cartelle rigenerabili): l'attività del progetto.
        var latest: TimeInterval = 0
        /// Cartelle rigenerabili trovate qui dentro: la data la decide l'attività di questa cartella.
        var pendingRebuildable: [Int] = []

        init(name: String, path: String, level: Int, context: FileKind?, rebuildable: Bool, insideRebuildable: Bool,
             inHome: Bool, modified: Date?) {
            self.name = name
            self.path = path
            self.level = level
            self.context = context
            self.rebuildable = rebuildable
            self.insideRebuildable = insideRebuildable
            self.inHome = inHome
            self.modified = modified
        }
    }

    // Attributi chiesti a getattrlistbulk (sys/attr.h). Scritti qui perché alcuni non entrano in Int32.
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnModTime: UInt32 = 0x0000_0400
    private static let cmnAccTime: UInt32 = 0x0000_1000
    private static let cmnFileID: UInt32 = 0x0200_0000
    private static let cmnError: UInt32 = 0x2000_0000
    private static let cmnReturned: UInt32 = 0x8000_0000
    private static let fileLinkCount: UInt32 = 0x0000_0001
    private static let fileAllocSize: UInt32 = 0x0000_0004
    private static let typeRegular: UInt32 = 1
    private static let typeDirectory: UInt32 = 2

    func scan(root: String = "/", progress: @escaping (ScanProgress) -> Void) -> DiskScanResult? {
        let started = Date()
        let volume = Self.volume(root)
        let home = NSHomeDirectory()
        let minKeep = max(Int64(1_000_000), volume.used / 200_000)

        var allowedDevices = Set<Int32>()
        for path in [root, "/System/Volumes/Data"] {
            var st = stat()
            if lstat(path, &st) == 0 { allowedDevices.insert(st.st_dev) }
        }
        // /System è il volume di sistema sigillato: non si tocca e non si può togliere nulla, quindi non si legge (la
        // lettura è più veloce) e finisce in "Non visibile" con gli snapshot.
        let skipped: Set<String> = ["/System", "/Volumes", "/dev", "/net", "/home", "/Network", "/.vol",
                                    "/.MobileBackups", "/.Spotlight-V100", "/.fseventsd"]

        stats = ScanStats()
        stats.minKeep = minKeep
        stats.devices = allowedDevices.sorted()

        var request = attrlist(bitmapcount: 5, reserved: 0,
                               commonattr: Self.cmnReturned | Self.cmnError | Self.cmnName | Self.cmnObjType
                                   | Self.cmnModTime | Self.cmnAccTime | Self.cmnFileID,
                               volattr: 0, dirattr: 0, fileattr: Self.fileLinkCount | Self.fileAllocSize, forkattr: 0)
        let bufferSize = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var nodes: [DiskNode] = []
        nodes.reserveCapacity(50_000)
        var findings = ScanFindings()
        var seenLinks = Set<UInt64>()
        var state = ScanProgress()
        var lastReport = Date.distantPast
        var rootIndex = -1
        var stopped = false

        func report(force: Bool = false) {
            let now = Date()
            if force || now.timeIntervalSince(lastReport) >= 0.25 {
                lastReport = now
                progress(state)
            }
        }

        func unreadable(_ path: String, _ code: Int32) {
            findings.unreadable += 1
            stats.unreadable += 1
            if stats.unreadableSamples.count < 15 {
                stats.unreadableSamples.append(path + " (" + String(cString: strerror(code)) + ")")
            }
        }

        /// Chiude una cartella: somma nel genitore, nodo se è abbastanza grande.
        func close(_ frame: Frame, parent: Frame?) {
            stats.closed += 1
            // La cartella decide la data delle cartelle rigenerabili trovate dentro di lei.
            for i in frame.pendingRebuildable {
                let latest = max(frame.latest, frame.modified?.timeIntervalSince1970 ?? 0)
                findings.rebuildable[i].date = latest > 0 ? Date(timeIntervalSince1970: latest) : nil
            }
            if frame.rebuildable, frame.size >= 50_000_000, let parent {
                findings.rebuildable.append(FoundItem(path: frame.path, size: frame.size, date: nil))
                parent.pendingRebuildable.append(findings.rebuildable.count - 1)
            }
            if let parent {
                parent.size += frame.size
                parent.items += frame.items + 1
                for k in 0..<parent.kinds.count { parent.kinds[k] += frame.kinds[k] }
                if !frame.insideRebuildable || parent.insideRebuildable { parent.latest = max(parent.latest, frame.latest) }
            }
            if parent == nil || frame.size >= minKeep {
                let index = Self.makeNode(frame, in: &nodes)
                if let parent { parent.kept.append(index) } else { rootIndex = index }
            } else if let parent {
                parent.smallSize += frame.size
                parent.smallItems += frame.items + 1
            }
        }

        /// Legge una cartella con getattrlistbulk (una chiamata per decine di voci, niente stat per file), poi scende
        /// nelle sottocartelle. Ricorsiva: la profondità è quella delle cartelle, poche decine di livelli.
        func walk(_ path: String, name: String, level: Int, modified: TimeInterval, parent: Frame?) {
            if stopped { return }
            if isCancelled {
                stopped = true
                stats.cancelled = true
                return
            }
            let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            if fd >= 0, level > 0 {
                var st = stat()
                if fstat(fd, &st) == 0, !allowedDevices.contains(st.st_dev) {
                    Darwin.close(fd)
                    stats.otherDevice += 1
                    return
                }
            }
            let rebuildable = !(parent?.insideRebuildable ?? false) && Self.isRebuildable(name, parent: parent?.name)
            let frame = Frame(name: name, path: path, level: level,
                              context: Self.context(name, path: path, level: level, parent: parent?.context),
                              rebuildable: rebuildable,
                              insideRebuildable: rebuildable || (parent?.insideRebuildable ?? false),
                              inHome: path.hasPrefix(home + "/"),
                              modified: modified > 0 ? Date(timeIntervalSince1970: modified) : nil)
            stats.directories += 1
            if level <= 3 { state.current = path }
            guard fd >= 0 else {
                unreadable(path, errno)
                close(frame, parent: parent)
                return
            }

            var subdirs: [(name: String, modified: TimeInterval)] = []
            while true {
                let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
                if count < 0 {
                    stats.errors += 1
                    unreadable(path, errno)
                    break
                }
                if count == 0 { break }
                var entry = buffer
                for _ in 0..<Int(count) {
                    let length = Int(entry.load(as: UInt32.self))
                    defer { entry = entry.advanced(by: length) }
                    let common = entry.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
                    let fileAttrs = entry.loadUnaligned(fromByteOffset: 4 + 12, as: UInt32.self)
                    var p = entry.advanced(by: 4 + 20)
                    if common & Self.cmnError != 0 {
                        let error = p.loadUnaligned(as: UInt32.self)
                        p = p.advanced(by: 4)
                        if error != 0 {
                            stats.errors += 1
                            continue
                        }
                    }
                    guard common & Self.cmnName != 0 else { continue }
                    let nameOffset = Int(p.loadUnaligned(as: Int32.self))
                    let nameLength = max(0, Int(p.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) - 1)
                    let namePointer = p.advanced(by: nameOffset).assumingMemoryBound(to: CChar.self)
                    p = p.advanced(by: 8)
                    var type: UInt32 = 0
                    if common & Self.cmnObjType != 0 {
                        type = p.loadUnaligned(as: UInt32.self)
                        p = p.advanced(by: 4)
                    }
                    var mtime: TimeInterval = 0
                    if common & Self.cmnModTime != 0 {
                        mtime = TimeInterval(p.loadUnaligned(as: Int.self))
                        p = p.advanced(by: 16)
                    }
                    var atime: TimeInterval = 0
                    if common & Self.cmnAccTime != 0 {
                        atime = TimeInterval(p.loadUnaligned(as: Int.self))
                        p = p.advanced(by: 16)
                    }
                    var fileID: UInt64 = 0
                    if common & Self.cmnFileID != 0 {
                        fileID = p.loadUnaligned(as: UInt64.self)
                        p = p.advanced(by: 8)
                    }
                    var links: UInt32 = 1
                    if fileAttrs & Self.fileLinkCount != 0 {
                        links = p.loadUnaligned(as: UInt32.self)
                        p = p.advanced(by: 4)
                    }
                    var size: Int64 = 0
                    if fileAttrs & Self.fileAllocSize != 0 {
                        size = p.loadUnaligned(as: Int64.self)
                    }

                    if type == Self.typeDirectory {
                        subdirs.append((String(cString: namePointer), mtime))
                        continue
                    }
                    if type == Self.typeRegular, links > 1, !seenLinks.insert(fileID).inserted {
                        stats.hardLinks += 1
                        continue
                    }
                    stats.files += 1
                    state.items += 1
                    state.bytes += size
                    frame.size += size
                    frame.items += 1
                    let kind: FileKind
                    if let context = frame.context {
                        kind = context
                    } else if type == Self.typeRegular {
                        kind = Self.kind(name: namePointer, length: nameLength)
                    } else {
                        kind = .other
                    }
                    frame.kinds[kind.rawValue] += size
                    if !frame.insideRebuildable { frame.latest = max(frame.latest, mtime) }

                    let used = Date(timeIntervalSince1970: max(mtime, atime))
                    if size >= minKeep {
                        let fileName = String(cString: namePointer)
                        nodes.append(DiskNode(name: fileName, size: size, kind: kind, isDirectory: false, items: 1,
                                              modified: Date(timeIntervalSince1970: mtime)))
                        frame.kept.append(nodes.count - 1)
                        if type == Self.typeRegular, frame.inHome {
                            let filePath = path + "/" + fileName
                            if size >= 1_000_000_000 { findings.bigFiles.append(FoundItem(path: filePath, size: size, date: used)) }
                            if size >= 20_000_000, Self.isInstaller(name: namePointer, length: nameLength) {
                                findings.installers.append(FoundItem(path: filePath, size: size, date: used))
                            }
                        }
                    } else {
                        frame.smallSize += size
                        frame.smallItems += 1
                        if type == Self.typeRegular, frame.inHome, size >= 20_000_000,
                           Self.isInstaller(name: namePointer, length: nameLength) {
                            findings.installers.append(FoundItem(path: path + "/" + String(cString: namePointer),
                                                                 size: size, date: used))
                        }
                    }
                }
            }
            Darwin.close(fd)
            report()

            let prefix = path.hasSuffix("/") ? path : path + "/"
            for sub in subdirs {
                let childPath = prefix + sub.name
                if level == 0, skipped.contains(childPath) {
                    stats.skipped += 1
                    continue
                }
                walk(childPath, name: sub.name, level: level + 1, modified: sub.modified, parent: frame)
                if stopped { return }
            }
            close(frame, parent: parent)
        }

        var rootStat = stat()
        let rootModified = lstat(root, &rootStat) == 0 ? TimeInterval(rootStat.st_mtimespec.tv_sec) : 0
        walk(root, name: root, level: 0, modified: rootModified, parent: nil)
        if stopped { return nil }

        stats.nodes = nodes.count
        guard rootIndex >= 0 else {
            stats.failure = "root folder never closed"
            return nil
        }
        report(force: true)

        // Ciò che la lettura non vede: snapshot, volumi di sistema, cartelle protette.
        let hidden = volume.used - nodes[rootIndex].size
        if hidden > minKeep {
            nodes.append(DiskNode(name: L("Non visibile: sistema, snapshot e cartelle protette"), size: hidden,
                                  kind: .system, isDirectory: false, isSynthetic: true, items: 0, modified: nil,
                                  parent: rootIndex))
            var children = nodes[rootIndex].children
            children.append(nodes.count - 1)
            children.sort { nodes[$0].size > nodes[$1].size }
            nodes[rootIndex].children = children
            nodes[rootIndex].size += hidden
        }

        findings.rebuildable.sort { $0.size > $1.size }
        findings.installers.sort { $0.size > $1.size }
        findings.bigFiles.sort { $0.size > $1.size }
        let tree = DiskTree(nodes: nodes, root: rootIndex, rootPath: root)
        return DiskScanResult(tree: tree, findings: findings, used: volume.used, total: volume.total,
                              duration: Date().timeIntervalSince(started))
    }

    /// Crea il nodo di una cartella chiusa: i figli tenuti, più un elemento con la somma dei piccoli.
    private static func makeNode(_ frame: Frame, in nodes: inout [DiskNode]) -> Int {
        var children = frame.kept
        if frame.smallSize > 0 {
            nodes.append(DiskNode(name: L("Altri %d elementi", frame.smallItems), size: frame.smallSize,
                                  kind: dominant(frame.kinds), isDirectory: false, isSynthetic: true,
                                  items: frame.smallItems, modified: nil))
            children.append(nodes.count - 1)
        }
        let kind = frame.context ?? dominant(frame.kinds)
        nodes.append(DiskNode(name: frame.name, size: frame.size, kind: kind, isDirectory: true, items: frame.items,
                              modified: frame.modified))
        let index = nodes.count - 1
        for c in children { nodes[c].parent = index }
        children.sort { nodes[$0].size > nodes[$1].size }
        nodes[index].children = children
        return index
    }

    private static func dominant(_ kinds: [Int64]) -> FileKind {
        var best = FileKind.other.rawValue
        var bestSize: Int64 = -1
        for (i, size) in kinds.enumerated() where size > bestSize {
            best = i
            bestSize = size
        }
        return FileKind(rawValue: best) ?? .other
    }

    // MARK: - Classificazione

    /// Il tipo che vale per tutto ciò che sta sotto una cartella (nil: si decide file per file).
    private static func context(_ name: String, path: String, level: Int, parent: FileKind?) -> FileKind? {
        if let parent { return parent }
        if name.hasSuffix(".app") { return .apps }
        if name.hasSuffix(".photoslibrary") { return .media }
        switch name {
        case "Caches", "Logs", ".cache": return .caches
        case "node_modules", "DerivedData", ".git", ".build", "Pods", "CoreSimulator", ".gradle", ".npm", ".cargo",
             ".rustup", ".venv", "venv", ".next", "Developer", "Xcode": return .development
        default: break
        }
        if level == 1 {
            switch name {
            case "System", "Library", "private", "usr", "bin", "sbin", "cores": return .system
            case "Applications": return .apps
            case "opt": return .development
            default: break
            }
        }
        return nil
    }

    /// Cartelle che si ricostruiscono: dipendenze e prodotti di compilazione.
    private static func isRebuildable(_ name: String, parent: String?) -> Bool {
        switch name {
        case "node_modules", ".build", "Pods", ".venv", "venv", ".next", ".gradle": return true
        case "DerivedData": return parent == "Xcode"
        default: return false
        }
    }

    private static let installerKeys: Set<UInt64> = Set(["dmg", "pkg", "xip", "iso", "mpkg"].map { extKey(Array($0.utf8)) })

    private static func isInstaller(name: UnsafeMutablePointer<CChar>, length: Int) -> Bool {
        guard let key = extensionKey(name, length: length) else { return false }
        return installerKeys.contains(key)
    }

    /// Estensione → tipo, letta dai byte del percorso senza creare stringhe: si fa per ogni file.
    private static let kinds: [UInt64: FileKind] = {
        var table: [UInt64: FileKind] = [:]
        let media = "jpg jpeg png heic heif gif tif tiff raw cr2 cr3 nef arw dng psd mov mp4 m4v avi mkv webm mp3 m4a aac wav aif aiff flac caf"
        let documents = "pdf doc docx xls xlsx ppt pptx key pages numbers txt rtf md csv epub odt ods odp"
        let apps = "dmg pkg mpkg xip iso"
        for (list, kind) in [(media, FileKind.media), (documents, .documents), (apps, .apps)] {
            for ext in list.split(separator: " ") { table[extKey(Array(ext.utf8))] = kind }
        }
        return table
    }()

    private static func kind(name: UnsafeMutablePointer<CChar>, length: Int) -> FileKind {
        guard let key = extensionKey(name, length: length) else { return .other }
        return kinds[key] ?? .other
    }

    /// I byte minuscoli dell'estensione (al massimo 7) in un numero, letti dalla fine del nome; nil se non c'è.
    private static func extensionKey(_ path: UnsafeMutablePointer<CChar>, length: Int) -> UInt64? {
        var i = length - 1
        var key: UInt64 = 0
        var count = 0
        while i >= 0 {
            let c = UInt8(bitPattern: path[i])
            if c == UInt8(ascii: ".") { break }
            if c == UInt8(ascii: "/") || count >= 7 { return nil }
            let lower = (c >= 65 && c <= 90) ? c + 32 : c
            key |= UInt64(lower) << UInt64(8 * count)
            count += 1
            i -= 1
        }
        guard i > 0, count > 0 else { return nil }
        return key
    }

    private static func extKey(_ bytes: [UInt8]) -> UInt64 {
        var key: UInt64 = 0
        for b in bytes {
            let lower = (b >= 65 && b <= 90) ? b + 32 : b
            key = key << 8 | UInt64(lower)
        }
        return key
    }

    // MARK: - Volume

    static func volume(_ path: String = "/") -> (total: Int64, used: Int64, free: Int64) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return (0, 0, 0) }
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        return (Int64(total), max(0, Int64(total) - free), free)
    }
}
