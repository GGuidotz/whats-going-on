// Attrezzi › Spazio: cosa occupa il disco, come GrandPerspective, e cosa si può togliere.
// Niente gira finché non premi "Analizza". La lettura (Sources/Core/DiskScanner.swift) va su una coda in background e
// si interrompe quando vuoi; chiusa la finestra, l'albero se ne va. La mappa si disegna in un solo Canvas, due livelli
// alla volta: si entra in una cartella con un doppio clic e si risale dalla barra del percorso.
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
    @Published var focus = 0
    @Published var selection: Int?
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

    func open(_ index: Int) {
        guard let tree, tree.nodes.indices.contains(index) else { return }
        let node = tree[index]
        if node.isDirectory, !node.children.isEmpty {
            focus = index
            selection = nil
        } else if node.parent >= 0 {
            focus = node.parent
            selection = index
        }
    }

    func up() {
        guard let tree, focus != tree.root, tree[focus].parent >= 0 else { return }
        selection = focus
        focus = tree[focus].parent
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

    func trash(_ items: [FoundItem]) {
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
                MainActor.assumeIsolated { self?.didTrash(moved, failed: failed) }
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
            row("Folders", "\(s.directories) opened, \(s.closed) closed, \(s.recovered) recovered")
            row("Files", "\(s.files), hard links skipped \(s.hardLinks)")
            row("Skipped", "\(s.skipped) by list, \(s.otherDevice) on other volumes")
            row("Problems", "\(s.unreadable) unreadable, \(s.errors) errors, \(s.statFailed) stat failed, \(s.cycles) cycles")
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
    @State private var hovered: Int?

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

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let selection = space.selection, let tree = space.tree, tree.nodes.indices.contains(selection) {
                        SelectionCard(space: space, index: selection)
                    }
                    if space.phase == .done { tipsSection }
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
            .frame(width: 330)
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
            case .idle, .done:
                Button {
                    space.start()
                } label: {
                    Label(space.phase == .done ? L("Analizza di nuovo") : L("Analizza il disco"),
                          systemImage: "magnifyingglass")
                }
                .glassProminentButton()
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: .command)
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
                breadcrumbs(tree)
                legend(tree)
                TreemapView(tree: tree, focus: space.focus, selection: space.selection, revision: space.revision,
                            hovered: $hovered,
                            select: { space.selection = $0 },
                            open: { space.open($0) },
                            report: { cells, size in
                                space.mapCells = cells
                                space.mapSize = size
                            })
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                statusLine(tree)
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
            Button { space.up() } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(space.focus == tree.root)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help(L("Cartella sopra") + " (⌘↑)")
                .accessibilityLabel(L("Cartella sopra"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    let chain = tree.ancestry(of: space.focus)
                    ForEach(Array(chain.enumerated()), id: \.element) { position, i in
                        if position > 0 {
                            Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                        }
                        Button(i == tree.root ? space.volumeName : tree[i].name) {
                            space.focus = i
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
            }
        }
    }

    private func statusLine(_ tree: DiskTree) -> some View {
        let shown = hovered ?? space.selection
        return HStack(spacing: 8) {
            if let i = shown, tree.nodes.indices.contains(i) {
                let node = tree[i]
                Image(systemName: node.isDirectory ? "folder" : (node.isSynthetic ? "square.grid.3x3" : "doc"))
                    .foregroundStyle(node.kind.color)
                    .accessibilityHidden(true)
                Text(node.name).lineLimit(1).truncationMode(.middle)
                Text(Format.diskBytes(node.size)).monospacedDigit().foregroundStyle(.secondary)
                Text(node.kind.title).foregroundStyle(.tertiary)
            } else {
                Text(L("Clic per scegliere, doppio clic per entrare in una cartella."))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.callout)
        .frame(height: 18)
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

// MARK: - Mappa

struct TreemapView: View {
    var tree: DiskTree
    var focus: Int
    var selection: Int?
    var revision: Int
    @Binding var hovered: Int?
    var select: (Int?) -> Void
    var open: (Int) -> Void
    /// Quante celle ha disegnato e in che spazio (per la sezione Debug).
    var report: (Int, CGSize) -> Void = { _, _ in }

    @State private var cells: [Cell] = []
    @State private var key = LayoutKey()

    struct Cell {
        var node: Int
        var rect: CGRect
        var depth: Int
    }

    struct LayoutKey: Equatable {
        var focus = -1
        var size = CGSize.zero
        var revision = -1
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                draw(&context, size: size)
            }
            .onAppear { relayout(geo.size) }
            .onChange(of: geo.size) { _, new in relayout(new) }
            .onChange(of: focus) { _, _ in relayout(geo.size) }
            .onChange(of: revision) { _, _ in relayout(geo.size) }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point): hovered = hit(point)
                case .ended: hovered = nil
                }
            }
            .onTapGesture(count: 2, coordinateSpace: .local) { point in
                if let i = hit(point) { open(i) }
            }
            .onTapGesture(count: 1, coordinateSpace: .local) { point in
                select(hit(point))
            }
            .contextMenu { menu }
        }
        .background(Color.primary.opacity(0.04))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Mappa dello spazio di %@", focus == tree.root ? L("tutto il disco") : tree[focus].name))
        .accessibilityValue(tree[focus].children.prefix(8)
            .map { "\(tree[$0].name), \(Format.diskBytes(tree[$0].size))" }.joined(separator: "; "))
    }

    @ViewBuilder private var menu: some View {
        if let i = hovered ?? selection, tree.nodes.indices.contains(i) {
            let node = tree[i]
            if node.isDirectory, !node.children.isEmpty {
                Button(L("Apri")) { open(i) }
            }
            if let path = tree.path(of: i) {
                Button(L("Mostra nel Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                Button(L("Copia il percorso")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
            }
        }
    }

    private func relayout(_ size: CGSize) {
        let newKey = LayoutKey(focus: focus, size: size, revision: revision)
        guard newKey != key, tree.nodes.indices.contains(focus) else { return }
        key = newKey
        var result: [Cell] = []
        let bounds = CGRect(origin: .zero, size: size)
        let top = tree[focus].children.filter { tree[$0].size > 0 }
        let rects = Treemap.layout(top.map { Double(tree[$0].size) }, in: bounds)
        for (node, rect) in zip(top, rects) where rect.width >= 1 && rect.height >= 1 {
            result.append(Cell(node: node, rect: rect, depth: 1))
            let n = tree[node]
            guard n.isDirectory, !n.children.isEmpty, rect.width > 44, rect.height > 40 else { continue }
            let inner = CGRect(x: rect.minX + 2, y: rect.minY + 17, width: rect.width - 4, height: rect.height - 19)
            let kids = n.children.filter { tree[$0].size > 0 }
            let innerRects = Treemap.layout(kids.map { Double(tree[$0].size) }, in: inner)
            for (k, r) in zip(kids, innerRects) where r.width >= 2 && r.height >= 2 {
                result.append(Cell(node: k, rect: r, depth: 2))
            }
        }
        cells = result
        report(result.count, size)
    }

    private func hit(_ point: CGPoint) -> Int? {
        cells.last { $0.rect.contains(point) }?.node
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        for cell in cells {
            let node = tree[cell.node]
            let rect = cell.rect.insetBy(dx: 0.75, dy: 0.75)
            guard rect.width > 0, rect.height > 0 else { continue }
            let shape = Path(roundedRect: rect, cornerRadius: cell.depth == 1 ? 4 : 2)
            let opacity: Double = node.isSynthetic ? 0.35 : (cell.depth == 1 ? 0.9 : 0.75)
            context.fill(shape, with: .color(node.kind.color.opacity(opacity)))
            if cell.depth == 2 {
                context.stroke(shape, with: .color(.black.opacity(0.18)), lineWidth: 0.5)
            }
            if cell.depth == 1, rect.width > 64, rect.height > 16 {
                var label = context
                label.clip(to: Path(rect.insetBy(dx: 4, dy: 1)))
                let ink = node.kind.ink
                label.draw(Text(node.name).font(.caption.weight(.semibold)).foregroundColor(ink),
                           at: CGPoint(x: rect.minX + 5, y: rect.minY + 2), anchor: .topLeading)
                if rect.height > 34, !(node.isDirectory && !node.children.isEmpty && rect.height > 40) {
                    label.draw(Text(Format.diskBytes(node.size)).font(.caption2).foregroundColor(ink.opacity(0.85)),
                               at: CGPoint(x: rect.minX + 5, y: rect.minY + 17), anchor: .topLeading)
                }
            }
        }
        for (index, color, width) in [(hovered, Color.white.opacity(0.9), 1.5), (selection, Color.accentColor, 2.5)] {
            guard let index, let cell = cells.last(where: { $0.node == index }) else { continue }
            context.stroke(Path(roundedRect: cell.rect.insetBy(dx: 1, dy: 1), cornerRadius: 3), with: .color(color),
                           lineWidth: width)
        }
    }
}

extension FileKind {
    /// Colori distinti tra loro e lontani dalla scala del carico: qui il colore dice il tipo, non un allarme.
    var color: Color {
        switch self {
        case .apps: Color(hue: 0.60, saturation: 0.62, brightness: 0.86)
        case .documents: Color(hue: 0.49, saturation: 0.60, brightness: 0.72)
        case .media: Color(hue: 0.80, saturation: 0.48, brightness: 0.82)
        case .development: Color(hue: 0.07, saturation: 0.66, brightness: 0.90)
        case .system: Color(white: 0.55)
        case .caches: Color(hue: 0.13, saturation: 0.70, brightness: 0.95)
        case .other: Color(hue: 0.34, saturation: 0.35, brightness: 0.68)
        }
    }

    /// Il colore del testo sopra il rettangolo.
    var ink: Color { self == .caches ? .black.opacity(0.8) : .white }
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
