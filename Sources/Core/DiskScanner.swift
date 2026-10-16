// La mappa dello spazio: legge tutto il disco una volta, solo quando lo chiedi, e ne fa un albero leggero.
//
// Come GrandPerspective, ma senza tenere in memoria ogni file: cartelle e file sotto una soglia (circa 1 MB, o
// 1/200000 dello spazio usato sui dischi molto pieni) finiscono sommati in un solo elemento "Altri n elementi". Così
// anche un disco con milioni di file resta qualche decina di migliaia di nodi.
//
// Lettura con getattrlistbulk: una chiamata restituisce nome, tipo, date e spazio allocato di decine di voci, senza
// uno stat per file (è il modo più veloce su APFS). I primi livelli si leggono in parallelo, una cartella per core:
// l'SSD regge molte richieste insieme e la lettura dura una frazione. Niente link simbolici, i collegamenti fisici contati una volta. Si parte da "/" e si resta sui due volumi del disco di avvio (sistema e dati): i firmlink di APFS
// (/Users, /Applications…) portano già ai dati, quindi /System (con /System/Volumes) e i dischi esterni in /Volumes
// restano fuori.
// Lo spazio che la lettura non vede (snapshot di Time Machine, volumi di sistema, cartelle protette) diventa un
// elemento a parte, "Non visibile", perché i conti tornino con lo spazio usato.
//
// Durante la lettura si annotano anche le cose che di solito si possono togliere: cartelle rigenerabili dei progetti
// (node_modules accanto a package.json, target accanto a Cargo.toml…), installer nei Download, file molto grandi. I consigli li scrive SpaceAdvisor.

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
    /// Un nome da mostrare al posto di quello della cartella ("Cache di npm" per _cacache).
    var label: String? = nil
    /// Per le cartelle dei progetti: lo strumento che le crea e se si rifanno sul Mac o si riscaricano.
    var artifact: DevArtifact? = nil
    var id: String { path }
    var name: String { label ?? (path as NSString).lastPathComponent }
}

/// Una cartella prodotta da uno strumento di sviluppo, riconosciuta dal file di progetto accanto (Cargo.toml per
/// target, package.json per node_modules…) o dentro (pyvenv.cfg per un ambiente Python). Senza il file non conta:
/// una cartella "target" o "build" qualsiasi può essere tua.
struct DevArtifact: Equatable {
    /// Lo strumento: "Node.js", "Rust"…
    var tool: String
    /// true: si riscarica da internet (dipendenze); false: si ricompila sul Mac.
    var refetch: Bool
    /// Il comando che la rifà, da mostrare.
    var command: String
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
        let base = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path == rootPath || path.hasPrefix(base) else { return nil }
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
        /// Cosa la produce, se è rigenerabile.
        let artifact: DevArtifact?
        /// Per gli ambienti Python: il file che deve stare dentro la cartella perché conti.
        let requires: String?
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
        /// Sul volume di sistema (/usr, /bin…): serve a calcolare quanto del sistema resta fuori dalla lettura.
        var onSystemVolume = false
        /// Manifest trovati in questa cartella (Cargo.toml, pyvenv.cfg…): decidono se una sottocartella è
        /// davvero il prodotto di uno strumento.
        var manifests: Set<String> = []

        init(name: String, path: String, level: Int, context: FileKind?, artifact: DevArtifact?, requires: String?,
             insideRebuildable: Bool, inHome: Bool, modified: Date?) {
            self.name = name
            self.path = path
            self.level = level
            self.context = context
            self.rebuildable = artifact != nil
            self.artifact = artifact
            self.requires = requires
            self.insideRebuildable = insideRebuildable
            self.inHome = inHome
            self.modified = modified
        }

        /// Una copia vuota, con gli stessi caratteri: raccoglie i risultati di un lettore in parallelo.
        func emptyCopy() -> Frame {
            let copy = Frame(name: name, path: path, level: level, context: context, artifact: artifact,
                             requires: requires, insideRebuildable: insideRebuildable, inHome: inHome,
                             modified: modified)
            copy.onSystemVolume = onSystemVolume
            copy.manifests = manifests
            return copy
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
        var rootDevice: Int32 = -1
        for path in [root, "/System/Volumes/Data"] {
            var st = stat()
            if lstat(path, &st) == 0 {
                allowedDevices.insert(st.st_dev)
                if path == root { rootDevice = st.st_dev }
            }
        }
        // /System è il volume di sistema sigillato: non si tocca e non si può togliere nulla, quindi non si legge (la
        // lettura è più veloce) e finisce in "Non visibile" con gli snapshot.
        let skipped: Set<String> = ["/System", "/Volumes", "/dev", "/net", "/home", "/Network", "/.vol",
                                    "/.MobileBackups", "/.Spotlight-V100", "/.fseventsd"]

        let request = attrlist(bitmapcount: 5, reserved: 0,
                               commonattr: Self.cmnReturned | Self.cmnError | Self.cmnName | Self.cmnObjType
                                   | Self.cmnModTime | Self.cmnAccTime | Self.cmnFileID,
                               volattr: 0, dirattr: 0, fileattr: Self.fileLinkCount | Self.fileAllocSize, forkattr: 0)
        let shared = Shared(scanner: self, minKeep: minKeep, home: home, allowedDevices: allowedDevices,
                            rootDevice: rootDevice, skipped: skipped, request: request, progress: progress)

        var rootStat = stat()
        let rootModified = lstat(root, &rootStat) == 0 ? TimeInterval(rootStat.st_mtimespec.tv_sec) : 0
        let walker = Walker(shared: shared)
        walker.nodes.reserveCapacity(50_000)
        walker.walk(root, name: root, level: 0, modified: rootModified, parent: nil)

        stats = walker.stats
        stats.minKeep = minKeep
        stats.devices = allowedDevices.sorted()
        if isCancelled {
            stats.cancelled = true
            return nil
        }
        var nodes = walker.nodes
        var findings = walker.findings
        let systemRead = walker.systemRead
        let rootIndex = walker.rootIndex
        stats.nodes = nodes.count
        guard rootIndex >= 0 else {
            stats.failure = "root folder never closed"
            return nil
        }
        shared.report()

        // Ciò che la lettura non vede, diviso dove si può misurare: il resto del volume di sistema, gli altri volumi
        // dello stesso disco (memoria virtuale, avvio, aggiornamenti) e, quello che avanza, snapshot e cartelle protette.
        // Solo per tutto il disco: di una cartella si legge tutto quello che c'è.
        let hidden = volume.used - nodes[rootIndex].size
        if root == "/", hidden > minKeep {
            var pieces: [(String, Int64)] = []
            if let systemUsed = Self.volumeSpaceUsed(root) {
                pieces.append((L("macOS (volume di sistema)"), systemUsed - systemRead))
            }
            for v in Self.otherVolumes() { pieces.append((v.name, v.used)) }
            var left = hidden
            var parts: [Int] = []
            for (name, size) in pieces.sorted(by: { $0.1 > $1.1 }) where size >= minKeep && left > 0 {
                let shown = min(size, left)
                nodes.append(DiskNode(name: name, size: shown, kind: .system, isDirectory: false, isSynthetic: true,
                                      items: 0, modified: nil))
                parts.append(nodes.count - 1)
                left -= shown
            }
            if left >= minKeep {
                nodes.append(DiskNode(name: L("Snapshot locali, cartelle protette e spazio riservato"), size: left,
                                      kind: .system, isDirectory: false, isSynthetic: true, items: 0, modified: nil))
                parts.append(nodes.count - 1)
            }
            nodes.append(DiskNode(name: L("Non visibile alla lettura"), size: hidden, kind: .system,
                                  isDirectory: !parts.isEmpty, isSynthetic: true, items: 0, modified: nil,
                                  parent: rootIndex))
            let hiddenIndex = nodes.count - 1
            parts.sort { nodes[$0].size > nodes[$1].size }
            for i in parts { nodes[i].parent = hiddenIndex }
            nodes[hiddenIndex].children = parts
            var children = nodes[rootIndex].children
            children.append(hiddenIndex)
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

    // MARK: - Lettura in parallelo

    /// Ciò che i lettori condividono: impostazioni, collegamenti fisici già visti, avanzamento, buffer.
    private final class Shared: @unchecked Sendable {
        let scanner: DiskScanner
        let minKeep: Int64
        let home: String
        let allowedDevices: Set<Int32>
        let rootDevice: Int32
        let skipped: Set<String>
        let request: attrlist
        /// Fino a questo livello le sottocartelle si leggono in parallelo, una per core: più in basso ogni lettore
        /// continua da solo, così il lavoro si divide bene senza un lettore per ogni cartellina.
        let splitDepth = 6
        static let bufferSize = 128 * 1024

        private let lock = NSLock()
        private var links = Set<UInt64>()
        private var state = ScanProgress()
        private var lastReport = Date.distantPast
        private var buffers: [UnsafeMutableRawPointer] = []
        private let progress: (ScanProgress) -> Void

        init(scanner: DiskScanner, minKeep: Int64, home: String, allowedDevices: Set<Int32>, rootDevice: Int32,
             skipped: Set<String>, request: attrlist, progress: @escaping (ScanProgress) -> Void) {
            self.scanner = scanner
            self.minKeep = minKeep
            self.home = home
            self.allowedDevices = allowedDevices
            self.rootDevice = rootDevice
            self.skipped = skipped
            self.request = request
            self.progress = progress
        }

        deinit { for b in buffers { b.deallocate() } }

        var cancelled: Bool { scanner.isCancelled }

        /// Un file con più collegamenti fisici conta una volta sola, chiunque lo trovi per primo.
        func firstLink(_ id: UInt64) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return links.insert(id).inserted
        }

        /// Somma ciò che un lettore ha appena letto e, ogni quarto di secondo, lo racconta.
        func add(items: Int, bytes: Int64, current: String?) {
            lock.lock()
            state.items += items
            state.bytes += bytes
            if let current { state.current = current }
            let now = Date()
            guard now.timeIntervalSince(lastReport) >= 0.25 else {
                lock.unlock()
                return
            }
            lastReport = now
            let snapshot = state
            lock.unlock()
            progress(snapshot)
        }

        func report() {
            lock.lock()
            let snapshot = state
            lock.unlock()
            progress(snapshot)
        }

        func takeBuffer() -> UnsafeMutableRawPointer {
            lock.lock()
            if let buffer = buffers.popLast() {
                lock.unlock()
                return buffer
            }
            lock.unlock()
            return UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 16)
        }

        func giveBack(_ buffer: UnsafeMutableRawPointer) {
            lock.lock()
            buffers.append(buffer)
            lock.unlock()
        }
    }

    /// Un lettore: legge un pezzo d'albero e ne tiene nodi, scoperte e conti. Le sottocartelle dei primi livelli
    /// vanno a lettori nuovi, in parallelo; finiti, i loro nodi si uniscono a questi.
    private final class Walker {
        let shared: Shared
        var nodes: [DiskNode] = []
        var findings = ScanFindings()
        var stats = ScanStats()
        var systemRead: Int64 = 0
        var rootIndex = -1
        /// Per i lettori in parallelo: la copia vuota della cartella genitore, dove si sommano i risultati.
        var holder: Frame?

        init(shared: Shared) { self.shared = shared }

        private func unreadable(_ path: String, _ code: Int32) {
            findings.unreadable += 1
            stats.unreadable += 1
            if stats.unreadableSamples.count < 15 {
                stats.unreadableSamples.append(path + " (" + String(cString: strerror(code)) + ")")
            }
        }

        /// Chiude una cartella: somma nel genitore, nodo se è abbastanza grande.
        private func close(_ frame: Frame, parent: Frame?) {
            stats.closed += 1
            // La cartella decide la data delle cartelle rigenerabili trovate dentro di lei.
            for i in frame.pendingRebuildable {
                let latest = max(frame.latest, frame.modified?.timeIntervalSince1970 ?? 0)
                findings.rebuildable[i].date = latest > 0 ? Date(timeIntervalSince1970: latest) : nil
            }
            if let artifact = frame.artifact, frame.size >= 10_000_000, let parent,
               frame.requires.map({ frame.manifests.contains($0) }) ?? true {
                findings.rebuildable.append(FoundItem(path: frame.path, size: frame.size, date: nil, artifact: artifact))
                parent.pendingRebuildable.append(findings.rebuildable.count - 1)
            }
            if let parent {
                parent.size += frame.size
                parent.items += frame.items + 1
                for k in 0..<parent.kinds.count { parent.kinds[k] += frame.kinds[k] }
                if !frame.insideRebuildable || parent.insideRebuildable { parent.latest = max(parent.latest, frame.latest) }
            }
            if parent == nil || frame.size >= shared.minKeep {
                let index = DiskScanner.makeNode(frame, in: &nodes)
                if let parent { parent.kept.append(index) } else { rootIndex = index }
            } else if let parent {
                parent.smallSize += frame.size
                parent.smallItems += frame.items + 1
            }
        }

        /// Unisce un lettore finito: i suoi nodi in coda ai nostri (con gli indici spostati), i suoi conti nella
        /// cartella `frame`.
        private func merge(_ other: Walker, into frame: Frame) {
            guard let held = other.holder else { return }
            let offset = nodes.count
            let rebuildableOffset = findings.rebuildable.count
            nodes.reserveCapacity(nodes.count + other.nodes.count)
            for var node in other.nodes {
                if !node.children.isEmpty { node.children = node.children.map { $0 + offset } }
                if node.parent >= 0 { node.parent += offset }
                nodes.append(node)
            }
            findings.rebuildable += other.findings.rebuildable
            findings.installers += other.findings.installers
            findings.bigFiles += other.findings.bigFiles
            findings.unreadable += other.findings.unreadable
            systemRead += other.systemRead

            let s = other.stats
            stats.directories += s.directories
            stats.files += s.files
            stats.closed += s.closed
            stats.unreadable += s.unreadable
            stats.errors += s.errors
            stats.skipped += s.skipped
            stats.otherDevice += s.otherDevice
            stats.hardLinks += s.hardLinks
            for sample in s.unreadableSamples where stats.unreadableSamples.count < 15 {
                stats.unreadableSamples.append(sample)
            }

            frame.size += held.size
            frame.items += held.items
            for k in 0..<frame.kinds.count { frame.kinds[k] += held.kinds[k] }
            frame.latest = max(frame.latest, held.latest)
            frame.smallSize += held.smallSize
            frame.smallItems += held.smallItems
            frame.kept += held.kept.map { $0 + offset }
            frame.pendingRebuildable += held.pendingRebuildable.map { $0 + rebuildableOffset }
        }

        /// Legge una cartella con getattrlistbulk (una chiamata per decine di voci, niente stat per file), poi scende
        /// nelle sottocartelle. Ricorsiva: la profondità è quella delle cartelle, poche decine di livelli.
        func walk(_ path: String, name: String, level: Int, modified: TimeInterval, parent: Frame?) {
            if shared.cancelled { return }
            let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            var device: Int32 = -1
            if fd >= 0 {
                var st = stat()
                if fstat(fd, &st) == 0 {
                    device = st.st_dev
                    if level > 0, !shared.allowedDevices.contains(device) {
                        Darwin.close(fd)
                        stats.otherDevice += 1
                        return
                    }
                }
            }
            let found = (parent?.insideRebuildable ?? true) ? nil : DiskScanner.artifact(name, parent: parent)
            let frame = Frame(name: name, path: path, level: level,
                              context: DiskScanner.context(name, path: path, level: level, parent: parent?.context),
                              artifact: found?.artifact, requires: found?.requires,
                              insideRebuildable: found != nil || (parent?.insideRebuildable ?? false),
                              inHome: path.hasPrefix(shared.home + "/"),
                              modified: modified > 0 ? Date(timeIntervalSince1970: modified) : nil)
            frame.onSystemVolume = device >= 0 ? device == shared.rootDevice : (parent?.onSystemVolume ?? false)
            stats.directories += 1
            guard fd >= 0 else {
                unreadable(path, errno)
                close(frame, parent: parent)
                return
            }

            let minKeep = shared.minKeep
            var request = shared.request
            let buffer = shared.takeBuffer()
            let bufferSize = Shared.bufferSize
            var readItems = 0
            var readBytes: Int64 = 0
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
                    if common & DiskScanner.cmnError != 0 {
                        let error = p.loadUnaligned(as: UInt32.self)
                        p = p.advanced(by: 4)
                        if error != 0 {
                            stats.errors += 1
                            continue
                        }
                    }
                    guard common & DiskScanner.cmnName != 0 else { continue }
                    let nameOffset = Int(p.loadUnaligned(as: Int32.self))
                    let nameLength = max(0, Int(p.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) - 1)
                    let namePointer = p.advanced(by: nameOffset).assumingMemoryBound(to: CChar.self)
                    p = p.advanced(by: 8)
                    var type: UInt32 = 0
                    if common & DiskScanner.cmnObjType != 0 {
                        type = p.loadUnaligned(as: UInt32.self)
                        p = p.advanced(by: 4)
                    }
                    var mtime: TimeInterval = 0
                    if common & DiskScanner.cmnModTime != 0 {
                        mtime = TimeInterval(p.loadUnaligned(as: Int.self))
                        p = p.advanced(by: 16)
                    }
                    var atime: TimeInterval = 0
                    if common & DiskScanner.cmnAccTime != 0 {
                        atime = TimeInterval(p.loadUnaligned(as: Int.self))
                        p = p.advanced(by: 16)
                    }
                    var fileID: UInt64 = 0
                    if common & DiskScanner.cmnFileID != 0 {
                        fileID = p.loadUnaligned(as: UInt64.self)
                        p = p.advanced(by: 8)
                    }
                    var links: UInt32 = 1
                    if fileAttrs & DiskScanner.fileLinkCount != 0 {
                        links = p.loadUnaligned(as: UInt32.self)
                        p = p.advanced(by: 4)
                    }
                    var size: Int64 = 0
                    if fileAttrs & DiskScanner.fileAllocSize != 0 {
                        size = p.loadUnaligned(as: Int64.self)
                    }

                    if type == DiskScanner.typeDirectory {
                        subdirs.append((String(cString: namePointer), mtime))
                        continue
                    }
                    if type == DiskScanner.typeRegular {
                        // Il manifest accanto: la cartella dei prodotti (target, .venv…) conta solo se c'è.
                        DiskScanner.noteManifest(namePointer, length: nameLength, in: frame)
                    }
                    if type == DiskScanner.typeRegular, links > 1, !shared.firstLink(fileID) {
                        stats.hardLinks += 1
                        continue
                    }
                    stats.files += 1
                    if frame.onSystemVolume { systemRead += size }
                    readItems += 1
                    readBytes += size
                    frame.size += size
                    frame.items += 1
                    let kind: FileKind
                    if let context = frame.context {
                        kind = context
                    } else if type == DiskScanner.typeRegular {
                        kind = DiskScanner.kind(name: namePointer, length: nameLength)
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
                        if type == DiskScanner.typeRegular, frame.inHome {
                            let filePath = path + "/" + fileName
                            if size >= 1_000_000_000 { findings.bigFiles.append(FoundItem(path: filePath, size: size, date: used)) }
                            if size >= 20_000_000, DiskScanner.isInstaller(name: namePointer, length: nameLength) {
                                findings.installers.append(FoundItem(path: filePath, size: size, date: used))
                            }
                        }
                    } else {
                        frame.smallSize += size
                        frame.smallItems += 1
                        if type == DiskScanner.typeRegular, frame.inHome, size >= 20_000_000,
                           DiskScanner.isInstaller(name: namePointer, length: nameLength) {
                            findings.installers.append(FoundItem(path: path + "/" + String(cString: namePointer),
                                                                 size: size, date: used))
                        }
                    }
                }
            }
            Darwin.close(fd)
            shared.giveBack(buffer)
            shared.add(items: readItems, bytes: readBytes, current: level <= 3 ? path : nil)

            let prefix = path.hasSuffix("/") ? path : path + "/"
            var children: [(path: String, name: String, modified: TimeInterval)] = []
            for sub in subdirs {
                let childPath = prefix + sub.name
                if level == 0, shared.skipped.contains(childPath) {
                    stats.skipped += 1
                    continue
                }
                children.append((childPath, sub.name, sub.modified))
            }

            if level < shared.splitDepth, children.count > 1 {
                // In parallelo: un lettore per sottocartella, quanti ne reggono i core. L'ordine dei risultati resta
                // quello delle cartelle, così la mappa è la stessa a ogni lettura.
                let jobs = children
                let shared = shared
                var results = [Walker?](repeating: nil, count: jobs.count)
                results.withUnsafeMutableBufferPointer { buffer in
                    // Ogni lettore scrive solo la sua casella: niente lucchetto.
                    let out = buffer
                    DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
                        let child = jobs[i]
                        let walker = Walker(shared: shared)
                        let held = frame.emptyCopy()
                        walker.holder = held
                        walker.walk(child.path, name: child.name, level: level + 1, modified: child.modified, parent: held)
                        out[i] = walker
                    }
                }
                if shared.cancelled { return }
                for case let walker? in results { merge(walker, into: frame) }
            } else {
                for child in children {
                    walk(child.path, name: child.name, level: level + 1, modified: child.modified, parent: frame)
                    if shared.cancelled { return }
                }
            }
            close(frame, parent: parent)
        }
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

    /// Cartelle che si ricostruiscono: dipendenze e prodotti di compilazione, solo se c'è il file di progetto che le
    /// spiega. `requires`: il file che deve stare dentro la cartella stessa (si controlla quando la si chiude).
    private static func artifact(_ name: String, parent: Frame?) -> (artifact: DevArtifact, requires: String?)? {
        guard let parent else { return nil }
        let m = parent.manifests
        func make(_ tool: String, _ refetch: Bool, _ command: String) -> (artifact: DevArtifact, requires: String?) {
            (DevArtifact(tool: tool, refetch: refetch, command: command), nil)
        }
        // Un "where" in un case con più nomi vale solo per l'ultimo: per questo un if per strumento.
        let node = m.contains("package.json")
        let gradle = m.contains("build.gradle") || m.contains("build.gradle.kts") || m.contains("settings.gradle")
            || m.contains("settings.gradle.kts")
        if node, name == "node_modules" { return make("Node.js", true, "npm install") }
        if node, [".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular"].contains(name) {
            return make("Node.js", false, "npm run build")
        }
        if name == ".build", m.contains("Package.swift") { return make("Swift", false, "swift build") }
        if name == "target", m.contains("Cargo.toml") { return make("Rust", false, "cargo build") }
        if name == "target", m.contains("pom.xml") { return make("Maven", false, "mvn package") }
        if gradle, name == "build" || name == ".gradle" { return make("Gradle", false, "gradle build") }
        if name == "Pods", m.contains("Podfile") { return make("CocoaPods", true, "pod install") }
        if name == ".dart_tool", m.contains("pubspec.yaml") { return make("Flutter", true, "flutter pub get") }
        if name == "obj" || name == "bin", m.contains("*.csproj") { return make(".NET", false, "dotnet build") }
        if name == ".venv" || name == "venv" {
            return (DevArtifact(tool: "Python", refetch: true, command: "pip install"), "pyvenv.cfg")
        }
        if name == "DerivedData", parent.name == "Xcode" { return make("Xcode", false, "Xcode") }
        return nil
    }

    /// I file di progetto che spiegano le cartelle qui sopra. Si guardano per ogni file, quindi prima la lunghezza.
    private static let manifestNames: [[UInt8]] = ["package.json", "Package.swift", "Cargo.toml", "pom.xml",
                                                   "build.gradle", "build.gradle.kts", "settings.gradle",
                                                   "settings.gradle.kts", "Podfile", "pubspec.yaml", "pyvenv.cfg"]
        .map { Array($0.utf8) }
    private static let manifestLengths = Set(manifestNames.map(\.count))
    private static let dotnetKeys: Set<UInt64> = Set(["csproj", "fsproj", "vbproj"].map { extKey(Array($0.utf8)) })

    private static func noteManifest(_ name: UnsafeMutablePointer<CChar>, length: Int, in frame: Frame) {
        if manifestLengths.contains(length) {
            for manifest in manifestNames where manifest.count == length && memcmp(name, manifest, length) == 0 {
                frame.manifests.insert(String(decoding: manifest, as: UTF8.self))
                return
            }
        }
        if length > 7, let key = extensionKey(name, length: length), dotnetKeys.contains(key) {
            frame.manifests.insert("*.csproj")
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

    /// Lo spazio usato da un solo volume APFS (i volumi di un disco condividono lo spazio libero).
    static func volumeSpaceUsed(_ path: String) -> Int64? {
        // ATTR_VOL_INFO | ATTR_VOL_SPACEUSED
        var request = attrlist(bitmapcount: 5, reserved: 0, commonattr: 0, volattr: 0x8000_0000 | 0x0080_0000,
                               dirattr: 0, fileattr: 0, forkattr: 0)
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { raw in
            getattrlist(path, &request, raw.baseAddress, raw.count, 0)
        }
        guard status == 0 else { return nil }
        let used = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
        return used > 0 ? used : nil
    }

    /// Gli altri volumi del disco di avvio (memoria virtuale, Preboot, aggiornamenti…), senza sistema e dati.
    static func otherVolumes() -> [(name: String, used: Int64)] {
        var list: UnsafeMutablePointer<statfs>?
        let count = Int(getmntinfo(&list, MNT_NOWAIT))
        guard count > 0, let list else { return [] }
        var mounts: [(from: String, on: String)] = []
        for i in 0..<count {
            let fs = list[i]
            let from = withUnsafeBytes(of: fs.f_mntfromname) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
            let on = withUnsafeBytes(of: fs.f_mntonname) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
            mounts.append((from, on))
        }
        /// "/dev/disk3s1s1" → ("disk3", "disk3s1"): il contenitore e il volume (senza lo snapshot).
        func ids(_ from: String) -> (container: String, volume: String)? {
            guard from.hasPrefix("/dev/disk") else { return nil }
            let rest = from.dropFirst(9)
            let disk = String(rest.prefix { $0.isNumber })
            guard !disk.isEmpty else { return nil }
            var volume = "disk" + disk
            let after = rest.dropFirst(disk.count)
            if after.first == "s" {
                volume += "s" + String(after.dropFirst().prefix { $0.isNumber })
            }
            return ("disk" + disk, volume)
        }
        guard let root = mounts.first(where: { $0.on == "/" }).flatMap({ ids($0.from) }) else { return [] }
        let data = mounts.first(where: { $0.on == "/System/Volumes/Data" }).flatMap { ids($0.from)?.volume }
        var seen: Set<String> = [root.volume]
        if let data { seen.insert(data) }
        var result: [(name: String, used: Int64)] = []
        for m in mounts {
            guard let id = ids(m.from), id.container == root.container, !seen.contains(id.volume),
                  let used = volumeSpaceUsed(m.on) else { continue }
            seen.insert(id.volume)
            let last = (m.on as NSString).lastPathComponent
            let name: String
            switch last {
            case "VM": name = L("Memoria virtuale (swap)")
            case "Preboot": name = L("Avvio di macOS (Preboot)")
            case "Update": name = L("Aggiornamenti di macOS")
            case "Recovery": name = L("Recupero di macOS")
            default: name = L("Volume di sistema %@", last)
            }
            result.append((name, used))
        }
        return result
    }

    static func volume(_ path: String = "/") -> (total: Int64, used: Int64, free: Int64) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return (0, 0, 0) }
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        return (Int64(total), max(0, Int64(total) - free), free)
    }
}
