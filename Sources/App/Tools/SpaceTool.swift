// Attrezzi › Spazio: cosa occupa il disco, come GrandPerspective, e cosa si può togliere.
// Niente gira finché non premi "Analizza". La lettura (Sources/Core/DiskScanner.swift) va su una coda in background e
// si interrompe quando vuoi; chiusa la finestra, l'albero se ne va. La mappa (SpaceMap.swift) mostra tutti i livelli in
// un'immagine; si entra con doppio clic o zoom avanti, si risale con zoom indietro o dalla barra del percorso.
// Ciò che togli va nel Cestino, sempre con conferma; solo dentro la tua cartella utente e in Applicazioni.

import AppKit
import SwiftUI

@MainActor
final class SpaceModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning(ScanProgress)
        case done
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var result: DiskScanResult?
    @Published private(set) var tips: [SpaceTip] = []
    /// La cartella mostrata dalla mappa. Si cambia con go(to:), che tiene la cronologia per Indietro.
    @Published private(set) var focus = 0
    @Published var selection: Int?
    /// Il rettangolo sotto il puntatore (o la riga dell'elenco): a parte, perché cambia a ogni movimento.
    let pointer = MapPointer()
    @Published var showInspector = true
    @Published var detail = MapDetail(rawValue: UserDefaults.standard.object(forKey: "mapDetail") as? Int ?? 1) ?? .medium {
        didSet { UserDefaults.standard.set(detail.rawValue, forKey: "mapDetail") }
    }
    /// Cerca: i nodi il cui nome contiene il testo, dal più grande.
    @Published var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    @Published private(set) var matches: [Int] = []
    private(set) var matchSet = Set<Int>()
    /// I file più grandi sotto la cartella mostrata e il percorso dove si concentra lo spazio.
    @Published private(set) var largestFiles: [Int] = []
    @Published private(set) var hotPath: [Int] = []
    private var history: [Int] = []
    private var searchWork: DispatchWorkItem?
    @Published private(set) var fullDiskAccess = FullDiskAccess.granted
    @Published private(set) var volume = DiskScanner.volume()
    @Published var message: String?
    /// Cresce a ogni modifica dell'albero: la mappa ricalcola la disposizione.
    @Published private(set) var revision = 0
    /// Per la sezione Debug: i conti dell'ultima lettura e cosa ha disegnato la mappa.
    @Published private(set) var stats: ScanStats?
    @Published private(set) var lastDuration: TimeInterval?
    @Published var mapCells = 0
    @Published var mapSize = CGSize.zero

    private var scanner: DiskScanner?
    let home = NSHomeDirectory()

    var tree: DiskTree? { result?.tree }

    /// L'Accesso completo al disco si può dare con la finestra aperta: si ricontrolla quando torni all'app.
    func refreshAccess() {
        let granted = FullDiskAccess.granted
        if granted != fullDiskAccess { fullDiskAccess = granted }
    }

    var volumeName: String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName)
            ?? "Macintosh HD"
    }

    func start() {
        scanner?.cancel()
        fullDiskAccess = FullDiskAccess.granted
        volume = DiskScanner.volume()
        let scanner = DiskScanner()
        self.scanner = scanner
        result = nil
        tips = []
        selection = nil
        message = nil
        stats = nil
        lastDuration = nil
        history = []
        matches = []
        matchSet = []
        largestFiles = []
        hotPath = []
        mapCells = 0
        phase = .scanning(ScanProgress())
        diag(.app, "space scan started (full disk access: \(fullDiskAccess))")
        let started = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = scanner.scan { progress in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.scanner === scanner, case .scanning = self.phase else { return }
                        self.phase = .scanning(progress)
                    }
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.scanner === scanner else { return }
                    self.scanner = nil
                    self.stats = scanner.stats
                    self.lastDuration = Date().timeIntervalSince(started)
                    guard let result else {
                        self.phase = .idle
                        let failure = scanner.stats.failure ?? "no result"
                        self.message = L("La lettura non ha dato una mappa. Apri Debug qui a destra e copiami il testo.")
                        diag(.app, "space scan failed: \(failure)")
                        return
                    }
                    self.result = result
                    self.focus = result.tree.root
                    self.refreshDerived()
                    self.runSearch()
                    self.tips = SpaceAdvisor.tips(for: result, home: self.home)
                    self.revision += 1
                    self.phase = .done
                    diag(.app, "space scan done: \(result.tree.nodes.count) nodes in \(Int(result.duration)) s, "
                        + "\(result.findings.unreadable) unreadable folders")
                }
            }
        }
    }

    func cancel() {
        scanner?.cancel()
        scanner = nil
        if case .scanning = phase { phase = .idle }
    }

    // MARK: - Navigazione

    var canGoBack: Bool { !history.isEmpty }
    var canZoomOut: Bool { tree.map { focus != $0.root } ?? false }

    /// Mostra una cartella; quella di prima va nella cronologia.
    func go(to index: Int) {
        guard let tree, tree.nodes.indices.contains(index), index != focus else { return }
        history.append(focus)
        if history.count > 50 { history.removeFirst() }
        focus = index
        refreshDerived()
    }

    func back() {
        guard let previous = history.popLast(), let tree, tree.nodes.indices.contains(previous) else { return }
        selection = focus
        focus = previous
        refreshDerived()
    }

    /// Doppio clic: entra in una cartella; su un file entra nella cartella che lo contiene e lo sceglie.
    func open(_ index: Int) {
        guard let tree, tree.nodes.indices.contains(index) else { return }
        let node = tree[index]
        if node.isDirectory, !node.children.isEmpty {
            go(to: index)
            selection = nil
        } else if node.parent >= 0 {
            if node.parent != focus { go(to: node.parent) }
            selection = index
        }
    }

    /// Zoom avanti sulla scelta (o, se è un file, sulla sua cartella).
    func zoomIn() {
        guard let selection else { return }
        open(selection)
    }

    /// Zoom indietro: la cartella che contiene quella mostrata.
    func up() {
        guard let tree, focus != tree.root, tree[focus].parent >= 0 else { return }
        let current = focus
        go(to: tree[focus].parent)
        selection = current
    }

    /// Livello su: sceglie la cartella che contiene la scelta (senza uscire dalla mappa).
    func selectParent() {
        guard let tree, let selection, selection != focus else { return }
        let parent = tree[selection].parent
        self.selection = parent == focus || parent < 0 ? nil : parent
    }

    /// Livello giù: sceglie l'elemento più grande dentro la scelta (o, senza scelta, il più grande della mappa).
    func selectChild() {
        guard let tree else { return }
        let base = selection ?? focus
        if let first = tree[base].children.first { selection = first }
    }

    /// Clic su una riga dell'elenco: la sceglie e, se non è nella mappa mostrata, apre la cartella che la contiene.
    func reveal(inMap index: Int) {
        guard let tree, tree.nodes.indices.contains(index) else { return }
        var i = index
        var inside = false
        while i >= 0 {
            if i == focus { inside = true; break }
            if i == tree.root { break }
            i = tree[i].parent
        }
        if !inside, tree[index].parent >= 0 { go(to: tree[index].parent) }
        selection = index
    }

    var selectedPath: String? { selection.flatMap { tree?.path(of: $0) } }

    /// Apri: un file con la sua app, una cartella entrandoci.
    func openSelection() {
        guard let tree, let selection else { return }
        if tree[selection].isDirectory, !tree[selection].children.isEmpty {
            open(selection)
        } else if let path = tree.path(of: selection) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    func quickLook() {
        guard let path = selectedPath else { return }
        QuickLook.shared.toggle(URL(fileURLWithPath: path))
    }

    func trashSelection() {
        guard let selection, let item = item(selection), canTrash(item.path) else { return }
        trash([item])
    }

    var canTrashSelection: Bool { selectedPath.map(canTrash) ?? false }

    // MARK: - Elenchi e ricerca

    /// Ricalcola ciò che dipende dalla cartella mostrata: costa qualche millisecondo, solo quando cambia.
    private func refreshDerived() {
        guard let tree, tree.nodes.indices.contains(focus) else {
            largestFiles = []
            hotPath = []
            return
        }
        // I file più grandi qui sotto: visita del sottoalbero (i nodi sono già solo quelli sopra la soglia).
        var files: [Int] = []
        var stack = [focus]
        while let i = stack.popLast() {
            let node = tree[i]
            if node.isDirectory {
                stack.append(contentsOf: node.children)
            } else if !node.isSynthetic {
                files.append(i)
            }
        }
        files.sort { tree[$0].size > tree[$1].size }
        largestFiles = Array(files.prefix(10))

        // Dove si concentra lo spazio: si scende finché il figlio più grande tiene almeno il 40% della cartella.
        var path: [Int] = []
        var i = focus
        while let first = tree[i].children.first, tree[first].isDirectory, !tree[first].isSynthetic,
              Double(tree[first].size) >= Double(tree[i].size) * 0.4, path.count < 8 {
            path.append(first)
            i = first
        }
        hotPath = path
    }

    private func scheduleSearch() {
        searchWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.runSearch() }
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func runSearch() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard let tree, !text.isEmpty else {
            matches = []
            matchSet = []
            return
        }
        var found: [Int] = []
        for (i, node) in tree.nodes.enumerated() where !node.isSynthetic && i != tree.root
            && node.parent >= 0 && node.name.localizedCaseInsensitiveContains(text) && tree.isAttached(i) {
            found.append(i)
        }
        found.sort { tree[$0].size > tree[$1].size }
        matchSet = Set(found)
        matches = Array(found.prefix(200))
    }

    // MARK: - Azioni

    /// Si può mettere nel Cestino: dentro la cartella utente (non le sue cartelle principali né quelle di Libreria) o
    /// un'app in Applicazioni.
    func canTrash(_ path: String) -> Bool {
        if path.hasPrefix("/Applications/") {
            return path.split(separator: "/").count == 2 && path.hasSuffix(".app")
        }
        guard path.hasPrefix(home + "/") else { return false }
        let parts = path.dropFirst(home.count + 1).split(separator: "/")
        if parts.first == "Library" { return parts.count >= 3 }
        return parts.count >= 2 || (parts.count == 1 && !Self.homeFolders.contains(String(parts[0])))
    }

    private static let homeFolders: Set<String> = ["Desktop", "Documents", "Downloads", "Library", "Movies", "Music",
                                                   "Pictures", "Public", "Applications", "Developer", ".Trash"]

    func reveal(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if path == home + "/.Trash" {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// - done: chiamato con i percorsi finiti nel Cestino (per chi tiene un elenco suo, come la ricerca Spotlight).
    func trash(_ items: [FoundItem], done: ((Set<String>) -> Void)? = nil) {
        let allowed = items.filter { canTrash($0.path) }
        guard !allowed.isEmpty else { return }
        let total = allowed.reduce(0) { $0 + $1.size }
        let names = allowed.prefix(6).map { "• " + $0.name }.joined(separator: "\n")
            + (allowed.count > 6 ? "\n" + L("e altri %d", allowed.count - 6) : "")
        guard ToolsAlert.confirm(
            title: allowed.count == 1 ? L("Spostare \"%@\" nel Cestino?", allowed[0].name)
                                      : L("Spostare %d elementi nel Cestino?", allowed.count),
            message: names + "\n\n" + L("Liberi %@ quando svuoti il Cestino. Fino ad allora puoi rimetterli dove erano.",
                                        Format.diskBytes(total)),
            button: L("Sposta nel Cestino")) else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var moved: [FoundItem] = []
            var failed: [String] = []
            for item in allowed {
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                    moved.append(item)
                } catch {
                    failed.append(item.name)
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.didTrash(moved, failed: failed)
                    done?(Set(moved.map(\.path)))
                }
            }
        }
    }

    private func didTrash(_ moved: [FoundItem], failed: [String]) {
        if var result {
            for item in moved { result.tree.remove(item.path, size: item.size) }
            let gone = Set(moved.map(\.path))
            result.findings.rebuildable.removeAll { gone.contains($0.path) }
            result.findings.installers.removeAll { gone.contains($0.path) }
            result.findings.bigFiles.removeAll { gone.contains($0.path) }
            // Se la cartella aperta è finita nel Cestino (o una che la contiene), si torna all'inizio.
            var i = focus
            while i != result.tree.root, i >= 0 {
                let parent = result.tree[i].parent
                if parent < 0 || !result.tree[parent].children.contains(i) {
                    focus = result.tree.root
                    break
                }
                i = parent
            }
            self.result = result
            tips = SpaceAdvisor.tips(for: result, home: home)
            revision += 1
            history = []
            refreshDerived()
            runSearch()
        }
        selection = nil
        var parts: [String] = []
        if !moved.isEmpty {
            parts.append(L("Nel Cestino: %d elementi, %@.", moved.count, Format.diskBytes(moved.reduce(0) { $0 + $1.size })))
        }
        if !failed.isEmpty {
            parts.append(L("Non spostati: %@. Prova dal Finder.", failed.prefix(4).joined(separator: ", ")))
        }
        message = parts.joined(separator: " ")
        diag(.app, "trashed \(moved.count) items, \(failed.count) failed")
    }

    /// Il testo della sezione Debug: in inglese come il report di diagnostica, da copiare in una segnalazione.
    /// Contiene percorsi di cartelle: resta sul Mac finché non lo copi tu.
    var debugReport: String {
        var out: [String] = []
        func row(_ key: String, _ value: String) { out.append("\(key): \(value)") }
        func bytes(_ b: Int64) -> String { "\(Format.diskBytes(b)) (\(b))" }
        row("App", SystemInfo.oneLine)
        switch phase {
        case .idle: row("Phase", stats?.failure != nil ? "failed" : "idle")
        case .scanning(let p): row("Phase", "scanning, \(p.items) items, \(Format.diskBytes(p.bytes))")
        case .done: row("Phase", "done")
        }
        row("Full Disk Access", fullDiskAccess ? "yes" : "no")
        row("Volume", "used \(bytes(volume.used)), total \(bytes(volume.total)), free \(bytes(volume.free))")
        if let lastDuration { row("Duration", String(format: "%.1f s", lastDuration)) }
        if let s = stats {
            row("Failure", s.failure ?? "none")
            row("Min kept size", bytes(s.minKeep))
            row("Devices", s.devices.map { String($0) }.joined(separator: ", "))
            row("Folders", "\(s.directories) opened, \(s.closed) closed")
            row("Files", "\(s.files), hard links skipped \(s.hardLinks)")
            row("Skipped", "\(s.skipped) by list, \(s.otherDevice) on other volumes")
            row("Problems", "\(s.unreadable) unreadable, \(s.errors) read errors")
            row("Nodes", "\(s.nodes)")
            if !s.unreadableSamples.isEmpty {
                out.append("Unreadable (first \(s.unreadableSamples.count)):")
                out += s.unreadableSamples.map { "  " + $0 }
            }
        } else {
            row("Scan", "none yet")
        }
        if let tree {
            let root = tree[tree.root]
            row("Tree", "\(tree.nodes.count) nodes, root \(bytes(root.size)), \(root.children.count) children")
            row("Map", "focus \(focus), \(mapCells) cells in \(Int(mapSize.width))×\(Int(mapSize.height)) pt")
            out.append("Largest in view:")
            for c in tree[focus].children.prefix(12) {
                let n = tree[c]
                out.append("  \(n.name) · \(Format.diskBytes(n.size)) · \(n.isDirectory ? "folder" : (n.isSynthetic ? "grouped" : "file")) · \(n.children.count) children")
            }
        }
        return out.joined(separator: "\n")
    }

    func item(_ index: Int) -> FoundItem? {
        guard let tree, let path = tree.path(of: index) else { return nil }
        return FoundItem(path: path, size: tree[index].size, date: tree[index].modified)
    }
}

// MARK: - Vista

struct SpaceView: View {
    @ObservedObject var space: SpaceModel
    @ObservedObject var mole: MoleRunner
    @ObservedObject var advice: AdviceModel
    @ObservedObject var prefs: Preferences
    var search: SpotlightSearch

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if !space.fullDiskAccess { accessBanner }
                content
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if space.showInspector || space.phase != .done {
                Divider()
                inspector
                    .frame(width: 330)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onAppear { space.refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            space.refreshAccess()
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let selection = space.selection, let tree = space.tree, tree.nodes.indices.contains(selection) {
                    SelectionCard(space: space, index: selection)
                }
                if space.phase == .done, let tree = space.tree {
                    SpaceListView(space: space, pointer: space.pointer, tree: tree)
                    tipsSection
                }
                ToolSection(title: L("Cerca su tutto il Mac"), symbol: "magnifyingglass") {
                    SpotlightBox(search: search, space: space)
                }
                ToolSection(title: L("Pulizia con Mole"), symbol: "sparkles") {
                    MoleBox(runner: mole, command: .clean)
                }
                if prefs.intelligence, let result = space.result {
                    ToolSection(title: L("Apple Intelligence (sperimentale)"), symbol: "apple.intelligence") {
                        AdviceBox(advice: advice) {
                            advice.ask(.space, context: SpaceAdvisor.summary(result, tips: space.tips, home: space.home))
                        }
                    }
                }
                SpaceDebugBox(space: space)
            }
            .padding(14)
        }
    }

    // MARK: In alto

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("%@ liberi", Format.diskBytes(space.volume.free)))
                    .font(.title2.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                Text(L("%@ usati di %@ su %@", Format.diskBytes(space.volume.used), Format.diskBytes(space.volume.total),
                       space.volumeName))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                FillBar(fraction: space.volume.total > 0 ? Double(space.volume.used) / Double(space.volume.total) : 0,
                        tint: Palette.load(Severity.remaining(space.volume.total > 0
                            ? Double(space.volume.free) / Double(space.volume.total) : 1)))
                    .frame(width: 220, height: 10)
            }
            Spacer()
            switch space.phase {
            case .scanning:
                Button(L("Interrompi")) { space.cancel() }
                    .glassButton()
            case .idle:
                Button {
                    space.start()
                } label: {
                    Label(L("Analizza il disco"), systemImage: "magnifyingglass")
                }
                .glassProminentButton()
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: .command)
            case .done:
                EmptyView()
            }
        }
        .padding(.top, 4)
    }

    private var accessBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.orange).accessibilityHidden(true)
            Text(L("Senza Accesso completo al disco restano fuori Mail, Messaggi, Safari, i backup e alcune cartelle di sistema."))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(L("Apri Impostazioni")) { FullDiskAccess.openSettings() }
                .glassButton()
        }
        .contentCard(padding: 10)
    }

    // MARK: Contenuto

    @ViewBuilder private var content: some View {
        switch space.phase {
        case .idle:
            emptyState
            if let message = space.message {
                Text(message).font(.callout).foregroundStyle(.orange).frame(maxWidth: .infinity)
            }
        case .scanning(let p):
            scanning(p)
        case .done:
            if let tree = space.tree {
                SpaceToolbar(space: space)
                breadcrumbs(tree)
                headline(tree)
                SpaceMapView(space: space, pointer: space.pointer, tree: tree)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                legend(tree)
                MapStatusLine(space: space, pointer: space.pointer, tree: tree)
                if let message = space.message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.split.2x2")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(L("Cosa occupa spazio"))
                .font(.title.weight(.semibold))
                .fontDesign(.rounded)
            Text(L("Una mappa del disco: ogni rettangolo è grande quanto lo spazio che occupa. A destra, cosa si può togliere senza pensieri. La lettura parte solo quando la chiedi e dura circa un minuto."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scanning(_ p: ScanProgress) -> some View {
        VStack(spacing: 12) {
            ProgressView(value: min(1, space.volume.used > 0 ? Double(p.bytes) / Double(space.volume.used) : 0))
                .frame(maxWidth: 420)
            Text(L("%@ letti, %@ elementi", Format.diskBytes(p.bytes), Format.number(Double(p.items), digits: 0)))
                .font(.title3)
                .monospacedDigit()
            Text(p.current)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func breadcrumbs(_ tree: DiskTree) -> some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    let chain = tree.ancestry(of: space.focus)
                    ForEach(Array(chain.enumerated()), id: \.element) { position, i in
                        if position > 0 {
                            Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                        }
                        Button(i == tree.root ? space.volumeName : tree[i].name) {
                            space.go(to: i)
                            space.selection = nil
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(i == space.focus ? Color.primary : Color.secondary)
                        .fontWeight(i == space.focus ? .semibold : .regular)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(Format.diskBytes(tree[space.focus].size))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
    }

    /// Una frase che dice dove sta lo spazio, prima ancora di guardare la mappa.
    @ViewBuilder private func headline(_ tree: DiskTree) -> some View {
        let focus = tree[space.focus]
        let here = space.focus == tree.root ? space.volumeName : focus.name
        if let last = space.hotPath.last, focus.size > 0 {
            let share = Format.percent(Double(tree[last].size) / Double(focus.size))
            let route = space.hotPath.map { tree[$0].name }.joined(separator: " › ")
            HStack(spacing: 4) {
                Text(L("Il %@ di %@ è in", share, here)).foregroundStyle(.secondary)
                Button(route) {
                    space.go(to: last)
                    space.selection = nil
                }
                .buttonStyle(.link)
                .lineLimit(1)
                .truncationMode(.head)
                Text("· " + Format.diskBytes(tree[last].size)).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)
        } else if let first = focus.children.first, focus.size > 0 {
            Text(L("La voce più grande qui è %@: %@ (%@).", tree[first].name, Format.diskBytes(tree[first].size),
                   Format.percent(Double(tree[first].size) / Double(focus.size))))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func legend(_ tree: DiskTree) -> some View {
        var totals = [Int64](repeating: 0, count: FileKind.allCases.count)
        for c in tree[space.focus].children { totals[tree[c].kind.rawValue] += tree[c].size }
        let shown = FileKind.allCases.filter { totals[$0.rawValue] > 0 }.sorted { totals[$0.rawValue] > totals[$1.rawValue] }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(shown) { kind in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2.5).fill(kind.color).frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(kind.title).foregroundStyle(.secondary)
                        Text(Format.diskBytes(totals[kind.rawValue])).monospacedDigit()
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                }
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.3x3.middle.filled").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(L("Tratteggio: piccoli elementi sommati")).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    // MARK: Consigli

    @ViewBuilder private var tipsSection: some View {
        ToolSection(title: L("Consigli"), symbol: "lightbulb") {
            if space.tips.isEmpty {
                Text(L("Niente di ovvio da togliere: lo spazio è usato da cose che ti servono. Guarda la mappa per i dettagli."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(space.tips) { TipCard(space: space, tip: $0) }
            }
        }
    }
}

/// La riga sotto la mappa: cosa c'è sotto il puntatore (o la scelta), con percorso, dimensione e tipo.
private struct MapStatusLine: View {
    @ObservedObject var space: SpaceModel
    @ObservedObject var pointer: MapPointer
    var tree: DiskTree

    var body: some View {
        let shown = pointer.hovered ?? space.selection
        HStack(spacing: 8) {
            if let i = shown, tree.nodes.indices.contains(i) {
                let node = tree[i]
                Image(systemName: node.isDirectory ? "folder" : (node.isSynthetic ? "square.grid.3x3" : "doc"))
                    .foregroundStyle(node.kind.color)
                    .accessibilityHidden(true)
                Text(tree.path(of: i).map { ($0 as NSString).abbreviatingWithTildeInPath } ?? node.name)
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(Format.diskBytes(node.size)).monospacedDigit().foregroundStyle(.secondary)
                Text(node.kind.title).foregroundStyle(.tertiary)
            } else {
                Text(L("Clic per scegliere, doppio clic o Invio per lo zoom, spazio per Quick Look."))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.callout)
        .frame(height: 18)
    }
}

// MARK: - Debug

/// I conti dell'ultima lettura, da copiare quando la mappa non fa quello che deve.
private struct SpaceDebugBox: View {
    @ObservedObject var space: SpaceModel
    @State private var expanded = false
    @State private var copied = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    Text(space.debugReport)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 220)
                HStack {
                    Button(L("Copia")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(space.debugReport, forType: .string)
                        copied = true
                    }
                    .glassButton()
                    .controlSize(.small)
                    if copied { Text(L("Copiato.")).font(.caption).foregroundStyle(.secondary) }
                }
                Text(L("Contiene i percorsi di alcune cartelle: resta sul Mac finché non lo copi tu."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        } label: {
            Label(L("Debug"), systemImage: "ladybug")
                .font(.headline)
        }
        .onChange(of: expanded) { _, _ in copied = false }
    }
}

// MARK: - Schede a destra

private struct SelectionCard: View {
    @ObservedObject var space: SpaceModel
    var index: Int

    var body: some View {
        if let tree = space.tree {
            let node = tree[index]
            let path = tree.path(of: index)
            VStack(alignment: .leading, spacing: 6) {
                Text(node.name).font(.headline).lineLimit(2).truncationMode(.middle)
                DetailLine(label: L("Dimensione"), value: Format.diskBytes(node.size))
                DetailLine(label: L("Tipo"), value: node.kind.title)
                if node.isDirectory { DetailLine(label: L("Elementi"), value: Format.number(Double(node.items), digits: 0)) }
                if let date = node.modified {
                    DetailLine(label: L("Modificato"), value: date.formatted(.dateTime.day().month().year()))
                }
                if let path, let hint = SpaceAdvisor.hint(for: path, home: space.home) {
                    Text(hint.prefix(1).uppercased() + hint.dropFirst() + ".")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } else if node.isSynthetic, node.items == 0 {
                    Text(L("Spazio che nessuna app può leggere: lo gestisce macOS."))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let path {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    HStack {
                        Button(L("Mostra nel Finder")) { space.reveal(path) }
                            .glassButton()
                        if space.canTrash(path), let item = space.item(index) {
                            Button(L("Sposta nel Cestino")) { space.trash([item]) }
                                .glassButton()
                        }
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            .contentCard(padding: 10)
        }
    }
}

private struct TipCard: View {
    @ObservedObject var space: SpaceModel
    var tip: SpaceTip
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: tip.symbol).foregroundStyle(.tint).frame(width: 18).accessibilityHidden(true)
                Text(tip.title).font(.callout.weight(.semibold))
                Spacer(minLength: 6)
                Text(Format.diskBytes(tip.bytes)).font(.callout).monospacedDigit()
            }
            Text(tip.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !tip.items.isEmpty {
                HStack(spacing: 8) {
                    switch tip.action {
                    case .trash:
                        Button(L("Sposta nel Cestino")) { space.trash(tip.items) }
                            .glassButton()
                    case .reveal:
                        Button(L("Apri nel Finder")) { space.reveal(tip.items[0].path) }
                            .glassButton()
                    case .info:
                        EmptyView()
                    }
                    if tip.action == .trash {
                        Button(expanded ? L("Nascondi") : L("Vedi %d elementi", tip.items.count)) {
                            expanded.toggle()
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .controlSize(.small)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tip.items) { item in
                        HStack(spacing: 6) {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                                .help(item.path)
                            Spacer(minLength: 4)
                            Text(Format.diskBytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                            Button { space.reveal(item.path) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.borderless)
                                .help(L("Mostra nel Finder"))
                                .accessibilityLabel(L("Mostra %@ nel Finder", item.name))
                            Button { space.trash([item]) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help(L("Sposta nel Cestino"))
                                .accessibilityLabel(L("Sposta %@ nel Cestino", item.name))
                        }
                        .font(.caption)
                    }
                }
                .padding(.top, 2)
            }
        }
        .contentCard(padding: 10)
    }
}
