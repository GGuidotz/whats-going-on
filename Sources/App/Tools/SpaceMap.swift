// Attrezzi › Spazio: la mappa. Come GrandPerspective mostra tutti i livelli insieme, ma piatta e leggibile: ogni
// cartella è un riquadro con il nome in testa e dentro le sue cose, i file sono pieni del colore del loro tipo, i
// piccoli sommati hanno un tratteggio. Si entra (zoom avanti) e si esce (zoom indietro) da una cartella alla volta.
//
// Efficienza: la mappa si disegna una volta in un'immagine, su una coda a parte, e si ridisegna solo quando cambiano
// cartella, dimensione della finestra, aspetto chiaro o scuro, oppure l'albero (dopo il Cestino). Passare con il
// puntatore, scegliere o cercare disegna solo una cornice sopra l'immagine.

import AppKit
import CoreText
import Quartz
import SwiftUI

/// Il rettangolo sotto il puntatore: un oggetto a parte, così muovere il mouse ridisegna solo chi lo guarda.
@MainActor
final class MapPointer: ObservableObject {
    @Published var hovered: Int?
}

// MARK: - Disegno

struct MapCell {
    var node: Int
    var rect: CGRect
    var depth: Int
    /// Cartella disegnata piena, senza il contenuto: al livello di dettaglio scelto finisce qui (zoom per vederla).
    var collapsed = false
}

/// Quanto mostra la mappa: non cambia la lettura, solo quanti livelli e quanto piccoli si disegnano.
enum MapDetail: Int, CaseIterable {
    case essential, medium, high, full

    var title: String {
        switch self {
        case .essential: L("Essenziale")
        case .medium: L("Medio")
        case .high: L("Alto")
        case .full: L("Tutto")
        }
    }

    /// Livelli sotto la cartella mostrata.
    var depth: Int {
        switch self {
        case .essential: 2
        case .medium: 3
        case .high: 5
        case .full: 48
        }
    }

    /// Lato e area minimi (in punti) perché un elemento abbia il suo rettangolo.
    var minSide: CGFloat {
        switch self {
        case .essential: 22
        case .medium: 12
        case .high: 5
        case .full: 2
        }
    }

    var minArea: CGFloat {
        switch self {
        case .essential: 1_400
        case .medium: 400
        case .high: 60
        case .full: 6
        }
    }
}

struct MapRender {
    struct Key: Equatable {
        var focus: Int
        var size: CGSize
        var revision: Int
        var dark: Bool
        var scale: CGFloat
        var detail: MapDetail
        /// Un tipo scelto nella legenda: gli altri si spengono in grigio.
        var highlight: FileKind?
    }

    var key: Key
    var image: CGImage
    /// Dai genitori ai figli: l'ultima cella che contiene un punto è la più profonda.
    var cells: [MapCell]
    /// Nodo → cella, per le cornici di scelta, puntatore e ricerca.
    var cellOf: [Int: Int]

    /// La cella da evidenziare per un nodo: la sua, o quella della cartella visibile più vicina.
    func cell(for node: Int, in tree: DiskTree) -> MapCell? {
        var i = node
        var steps = 0
        while i >= 0, steps < 512 {
            if let c = cellOf[i] { return cells[c] }
            if i == key.focus { return nil }
            i = tree.nodes.indices.contains(i) ? tree[i].parent : -1
            steps += 1
        }
        return nil
    }

    func hit(_ point: CGPoint) -> Int? {
        cells.last { $0.rect.contains(point) }?.node
    }
}

enum TreemapRenderer {
    static let headerHeight: CGFloat = 16
    static let maxCells = 80_000

    static func render(tree: DiskTree, key: MapRender.Key) -> MapRender? {
        let size = key.size
        guard size.width >= 20, size.height >= 20, tree.nodes.indices.contains(key.focus) else { return nil }

        // Disposizione: tutti i livelli, finché i rettangoli restano visibili.
        var cells: [MapCell] = []
        cells.reserveCapacity(8_000)

        func layChildren(of node: Int, in rect: CGRect, depth: Int) {
            let kids = tree[node].children.filter { tree[$0].size > 0 }
            guard !kids.isEmpty else { return }
            let rects = Treemap.layout(kids.map { Double(tree[$0].size) }, in: rect)
            let detail = key.detail
            for (k, r) in zip(kids, rects)
            where r.width >= detail.minSide && r.height >= detail.minSide && r.width * r.height >= detail.minArea {
                guard cells.count < maxCells else { return }
                lay(k, r, depth)
            }
        }

        func lay(_ node: Int, _ rect: CGRect, _ depth: Int) {
            let n = tree[node]
            let folder = n.isDirectory && !n.children.isEmpty
            let collapsed = folder && depth >= key.detail.depth
            cells.append(MapCell(node: node, rect: rect, depth: depth, collapsed: collapsed))
            guard folder, !collapsed else { return }
            let top: CGFloat = hasHeader(rect) ? headerHeight : 1.5
            let inner = CGRect(x: rect.minX + 1.5, y: rect.minY + top, width: rect.width - 3, height: rect.height - top - 1.5)
            guard inner.width >= 3, inner.height >= 3 else { return }
            layChildren(of: node, in: inner, depth: depth + 1)
        }

        layChildren(of: key.focus, in: CGRect(origin: .zero, size: size), depth: 1)

        // Disegno in un'immagine, in punti con l'origine in alto a sinistra.
        let scale = max(1, key.scale)
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        let dark = key.dark
        let background = CGColor(gray: dark ? 0.13 : 0.96, alpha: 1)
        let separator = CGColor(gray: dark ? 1 : 0, alpha: dark ? 0.14 : 0.16)
        let headerInk = CGColor(gray: dark ? 1 : 0, alpha: dark ? 0.86 : 0.78)
        ctx.setFillColor(background)
        ctx.fill(CGRect(origin: .zero, size: size))

        let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let detailFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        var palette: [FileKind: (fill: CGColor, folder: CGColor, ink: CGColor)] = [:]
        for kind in FileKind.allCases {
            if let highlight = key.highlight, highlight != kind {
                // Spento: grigio tenue, il testo resta leggibile.
                palette[kind] = (CGColor(gray: dark ? 0.32 : 0.82, alpha: 1),
                                 CGColor(gray: dark ? 1 : 0, alpha: 0.04),
                                 CGColor(gray: dark ? 1 : 0, alpha: 0.55))
                continue
            }
            let base = kind.nsColor
            palette[kind] = (base.cgColor,
                             base.withAlphaComponent(dark ? 0.20 : 0.16).cgColor,
                             kind.inkIsDark ? CGColor(gray: 0, alpha: 0.82) : CGColor(gray: 1, alpha: 1))
        }

        for cell in cells {
            let node = tree[cell.node]
            guard let colors = palette[node.kind] else { continue }
            let r = cell.rect
            if node.isDirectory, !node.children.isEmpty, !cell.collapsed {
                ctx.setFillColor(colors.folder)
                ctx.fill(r)
                ctx.setStrokeColor(separator)
                ctx.setLineWidth(0.5)
                ctx.stroke(r.insetBy(dx: 0.25, dy: 0.25))
                if hasHeader(r) {
                    let size = Format.diskBytes(node.size)
                    draw(node.name, font: titleFont, color: headerInk, in: ctx,
                         at: CGPoint(x: r.minX + 5, y: r.minY + 2), maxWidth: r.width - 10 - (r.width > 150 ? 60 : 0))
                    if r.width > 150 {
                        draw(size, font: detailFont, color: headerInk, in: ctx,
                             at: CGPoint(x: r.maxX - 62, y: r.minY + 3), maxWidth: 58, alignRight: true)
                    }
                }
            } else {
                let fill = r.insetBy(dx: 0.5, dy: 0.5)
                guard fill.width > 0, fill.height > 0 else { continue }
                if cell.collapsed {
                    // Cartella chiusa a questo livello di dettaglio: piena, più chiara di un file, con un bordo.
                    ctx.setFillColor(colors.fill.copy(alpha: 0.62) ?? colors.fill)
                    ctx.fill(fill)
                    ctx.setStrokeColor(separator)
                    ctx.setLineWidth(1)
                    ctx.stroke(fill.insetBy(dx: 0.5, dy: 0.5))
                } else if node.isSynthetic {
                    // Piccoli sommati e spazio non visibile: tinta leggera e tratteggio, si distinguono anche senza colore.
                    ctx.setFillColor(colors.fill.copy(alpha: 0.38) ?? colors.fill)
                    ctx.fill(fill)
                    if fill.width * fill.height > 120 { hatch(fill, in: ctx, color: separator) }
                } else {
                    ctx.setFillColor(colors.fill)
                    ctx.fill(fill)
                }
                if fill.width >= 56, fill.height >= 30 {
                    let ink = node.isSynthetic || cell.collapsed ? headerInk : colors.ink
                    draw(node.name, font: titleFont, color: ink, in: ctx,
                         at: CGPoint(x: fill.minX + 5, y: fill.minY + 3), maxWidth: fill.width - 10)
                    draw(Format.diskBytes(node.size), font: detailFont, color: ink, in: ctx,
                         at: CGPoint(x: fill.minX + 5, y: fill.minY + 17), maxWidth: fill.width - 10)
                }
            }
        }

        guard let image = ctx.makeImage() else { return nil }
        var cellOf: [Int: Int] = [:]
        cellOf.reserveCapacity(cells.count)
        for (i, cell) in cells.enumerated() where cellOf[cell.node] == nil { cellOf[cell.node] = i }
        return MapRender(key: key, image: image, cells: cells, cellOf: cellOf)
    }

    static func hasHeader(_ rect: CGRect) -> Bool { rect.width >= 60 && rect.height >= 38 }

    private static func hatch(_ rect: CGRect, in ctx: CGContext, color: CGColor) {
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(1)
        var x = rect.minX - rect.height
        while x < rect.maxX {
            ctx.move(to: CGPoint(x: x, y: rect.maxY))
            ctx.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 6
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Testo su una riga, accorciato con "…" se non entra. `point` è l'angolo in alto a sinistra.
    private static func draw(_ text: String, font: NSFont, color: CGColor, in ctx: CGContext, at point: CGPoint,
                             maxWidth: CGFloat, alignRight: Bool = false) {
        guard maxWidth > 8 else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if width > maxWidth {
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            guard let short = CTLineCreateTruncatedLine(line, Double(maxWidth), .end, token) else { return }
            line = short
            width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: alignRight ? point.x + maxWidth - width : point.x, y: point.y + font.ascender)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

/// Disegna su una coda a parte; se arrivano richieste mentre lavora, tiene solo l'ultima.
@MainActor
final class MapRenderer: ObservableObject {
    @Published private(set) var render: MapRender?
    private var running = false
    private var next: (tree: DiskTree, key: MapRender.Key)?
    private let queue = DispatchQueue(label: "local.whatsgoingon.treemap", qos: .userInitiated)

    func request(_ tree: DiskTree, _ key: MapRender.Key) {
        if render?.key == key, next == nil { return }
        next = (tree, key)
        startIfIdle()
    }

    private func startIfIdle() {
        guard !running, let job = next else { return }
        next = nil
        running = true
        queue.async { [weak self] in
            let result = TreemapRenderer.render(tree: job.tree, key: job.key)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.running = false
                    if let result { self.render = result }
                    self.startIfIdle()
                }
            }
        }
    }
}

// MARK: - Vista della mappa

struct SpaceMapView: View {
    @ObservedObject var space: SpaceModel
    @ObservedObject var pointer: MapPointer
    var tree: DiskTree
    @StateObject private var renderer = MapRenderer()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let render = renderer.render {
                    Image(decorative: render.image, scale: render.key.scale)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                Canvas { context, size in
                    drawOverlay(&context, size: size)
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point): pointer.hovered = hit(point, in: geo.size)
                case .ended: pointer.hovered = nil
                }
            }
            .onTapGesture(count: 2, coordinateSpace: .local) { point in
                if let i = hit(point, in: geo.size) { space.open(i) }
            }
            .onTapGesture(count: 1, coordinateSpace: .local) { point in
                space.selection = hit(point, in: geo.size)
            }
            .contextMenu { menu }
            .onAppear { request(geo.size) }
            .onChange(of: geo.size) { _, new in request(new) }
            .onChange(of: space.focus) { _, _ in request(geo.size) }
            .onChange(of: space.revision) { _, _ in request(geo.size) }
            .onChange(of: scheme) { _, _ in request(geo.size) }
            .onChange(of: space.detail) { _, _ in request(geo.size) }
            .onChange(of: space.kindFilter) { _, _ in request(geo.size) }
            .onChange(of: renderer.render?.cells.count ?? 0) { _, count in
                space.mapCells = count
                space.mapSize = geo.size
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            space.quickLook()
            return .handled
        }
        .onKeyPress(.return) {
            space.zoomIn()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Mappa dello spazio di %@", space.focus == tree.root ? L("tutto il disco") : tree[space.focus].name))
        .accessibilityValue(tree[space.focus].children.prefix(8)
            .map { "\(tree[$0].name), \(Format.diskBytes(tree[$0].size))" }.joined(separator: "; "))
        .accessibilityHint(L("L'elenco a destra mostra le stesse voci, dalla più grande."))
    }

    private func request(_ size: CGSize) {
        renderer.request(tree, MapRender.Key(focus: space.focus, size: size, revision: space.revision,
                                             dark: scheme == .dark, scale: displayScale, detail: space.detail,
                                             highlight: space.kindFilter))
    }

    /// Il punto nelle coordinate dell'immagine (durante un ridimensionamento l'immagine è ancora quella vecchia).
    private func hit(_ point: CGPoint, in size: CGSize) -> Int? {
        guard let render = renderer.render, size.width > 0, size.height > 0 else { return nil }
        let p = CGPoint(x: point.x * render.key.size.width / size.width, y: point.y * render.key.size.height / size.height)
        return render.hit(p)
    }

    private func drawOverlay(_ context: inout GraphicsContext, size: CGSize) {
        guard let render = renderer.render, render.key.size.width > 0, render.key.size.height > 0 else { return }
        let sx = size.width / render.key.size.width, sy = size.height / render.key.size.height
        func rect(_ cell: MapCell) -> CGRect {
            CGRect(x: cell.rect.minX * sx, y: cell.rect.minY * sy, width: cell.rect.width * sx, height: cell.rect.height * sy)
        }
        // Ricerca: cornice sui risultati visibili.
        if !space.matchSet.isEmpty {
            var path = Path()
            var drawn = 0
            for i in space.matches {
                guard drawn < 400, let cell = render.cell(for: i, in: tree) else { continue }
                path.addRect(rect(cell).insetBy(dx: 1, dy: 1))
                drawn += 1
            }
            context.stroke(path, with: .color(.yellow), lineWidth: 2)
            context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 0.5)
        }
        if let hovered = pointer.hovered, let cell = render.cell(for: hovered, in: tree) {
            let r = rect(cell).insetBy(dx: 0.5, dy: 0.5)
            context.fill(Path(r), with: .color(.white.opacity(0.18)))
            context.stroke(Path(r), with: .color(.white.opacity(0.95)), lineWidth: 1.5)
        }
        if let selection = space.selection, let cell = render.cell(for: selection, in: tree) {
            let r = rect(cell).insetBy(dx: 1, dy: 1)
            context.stroke(Path(r), with: .color(.black.opacity(0.45)), lineWidth: 4)
            context.stroke(Path(r), with: .color(.accentColor), lineWidth: 2.5)
        }
    }

    @ViewBuilder private var menu: some View {
        if let i = pointer.hovered ?? space.selection, tree.nodes.indices.contains(i) {
            let node = tree[i]
            if node.isDirectory, !node.children.isEmpty {
                Button(L("Zoom avanti")) { space.open(i) }
            }
            if let path = tree.path(of: i) {
                Button(L("Quick Look")) {
                    space.selection = i
                    space.quickLook()
                }
                Button(L("Mostra nel Finder")) { space.reveal(path) }
                Button(L("Copia il percorso")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
                if space.canTrash(path), let item = space.item(i) {
                    Divider()
                    Button(L("Sposta nel Cestino")) { space.trash([item]) }
                }
            }
        }
    }
}

// MARK: - Barra della mappa

/// I comandi di GrandPerspective, in una riga: navigazione, livello, azioni sulla scelta, ricerca.
/// Simboli monocromi sopra una mappa colorata, ognuno con nome e scorciatoia nel suggerimento.
struct SpaceToolbar: View {
    @ObservedObject var space: SpaceModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            group {
                tool(L("Indietro"), "chevron.backward", key: "[", enabled: space.canGoBack) { space.back() }
            }
            separator
            group {
                tool(L("Zoom indietro"), "minus.magnifyingglass", key: .upArrow, enabled: space.canZoomOut) { space.up() }
                tool(L("Zoom avanti"), "plus.magnifyingglass", key: .downArrow, enabled: space.selection != nil) { space.zoomIn() }
            }
            separator
            group {
                tool(L("Livello su"), "arrow.up.to.line", key: nil, enabled: space.selection != nil) { space.selectParent() }
                tool(L("Livello giù"), "arrow.down.to.line", key: nil, enabled: true) { space.selectChild() }
            }
            separator
            group {
                tool(L("Apri"), "arrow.up.forward.app", key: "o", enabled: space.selection != nil) { space.openSelection() }
                tool(L("Quick Look"), "eye", key: "y", enabled: space.selectedPath != nil) { space.quickLook() }
                tool(L("Mostra nel Finder"), "folder", key: nil, enabled: space.selectedPath != nil) {
                    if let path = space.selectedPath { space.reveal(path) }
                }
                tool(L("Sposta nel Cestino"), "trash", key: .delete, enabled: space.canTrashSelection) { space.trashSelection() }
            }
            separator
            Picker(L("Vista"), selection: $space.showList) {
                Image(systemName: "square.grid.2x2").accessibilityLabel(L("Mappa")).tag(false)
                Image(systemName: "list.bullet").accessibilityLabel(L("Elenco")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(L("Mappa o elenco: nell'elenco si ordina per colonna e si spuntano più voci per il Cestino."))
            separator
            DetailSlider(space: space)
                .disabled(space.showList)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(L("Cerca"), text: $space.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .frame(width: 150)
                if !space.query.isEmpty {
                    Button { space.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L("Cancella la ricerca"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .background {
                // ⌘F porta nella ricerca: un pulsante invisibile, solo per la scorciatoia.
                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            separator
            tool(L("Aggiorna"), "arrow.clockwise", key: "r", enabled: true) { space.start() }
            tool(L("Info"), "sidebar.trailing", key: "i", enabled: true) {
                withAnimation(.easeInOut(duration: 0.2)) { space.showInspector.toggle() }
            }
        }
        .controlSize(.regular)
    }

    private var separator: some View {
        Divider().frame(height: 16).padding(.horizontal, 4)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
    }

    private func tool(_ title: String, _ symbol: String, key: KeyEquivalent?, enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        let shortcut = key.map { "⌘" + Self.symbol(for: $0) }
        return Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
        .accessibilityLabel(title)
        .modifier(OptionalShortcut(key: key))
    }

    private static func symbol(for key: KeyEquivalent) -> String {
        switch key {
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .delete: "⌫"
        default: String(key.character).uppercased()
        }
    }
}

/// Il livello di dettaglio della mappa: da "solo le voci grandi" a "tutto, come GrandPerspective".
private struct DetailSlider: View {
    @ObservedObject var space: SpaceModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.2x2").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            Slider(value: Binding(get: { Double(space.detail.rawValue) },
                                  set: { space.detail = MapDetail(rawValue: Int($0.rounded())) ?? .medium }),
                   in: 0...Double(MapDetail.allCases.count - 1), step: 1)
                .frame(width: 90)
                .accessibilityLabel(L("Dettaglio della mappa"))
                .accessibilityValue(space.detail.title)
            Image(systemName: "square.grid.4x3.fill").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(space.detail.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
        }
        .help(L("Dettaglio della mappa: quanti livelli e quanto piccoli. Le cartelle piene si aprono con lo zoom."))
    }
}

private struct OptionalShortcut: ViewModifier {
    var key: KeyEquivalent?

    @ViewBuilder func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}

// MARK: - Elenco delle voci più grandi

/// La stessa informazione della mappa, in ordine: le voci della cartella mostrata, i file più grandi lì sotto, o i
/// risultati della ricerca. Passare su una riga la evidenzia nella mappa.
struct SpaceListView: View {
    @ObservedObject var space: SpaceModel
    /// Non osservato: l'elenco lo scrive passando sulle righe, non serve ridisegnarlo a ogni movimento.
    var pointer: MapPointer
    var tree: DiskTree

    var body: some View {
        if !space.query.trimmingCharacters(in: .whitespaces).isEmpty {
            ToolSection(title: L("Risultati"), symbol: "magnifyingglass") {
                if space.matches.isEmpty {
                    Text(L("Nessun elemento con questo nome.")).font(.callout).foregroundStyle(.secondary)
                } else {
                    Text(space.matchSet.count > space.matches.count
                         ? L("%d elementi, i primi %d per dimensione.", space.matchSet.count, space.matches.count)
                         : L("%d elementi.", space.matches.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    rows(Array(space.matches.prefix(40)), total: nil, showFolder: true)
                }
            }
        } else {
            ToolSection(title: L("Le più grandi qui"), symbol: "chart.bar.doc.horizontal") {
                rows(Array(tree[space.focus].children.prefix(12)), total: tree[space.focus].size, showFolder: false)
            }
            if !space.largestFiles.isEmpty {
                ToolSection(title: L("File più grandi"), symbol: "doc") {
                    rows(space.largestFiles, total: tree[space.focus].size, showFolder: true)
                }
            }
        }
    }

    private func rows(_ items: [Int], total: Int64?, showFolder: Bool) -> some View {
        let top = items.first.map { max(1, tree[$0].size) } ?? 1
        return VStack(spacing: 2) {
            ForEach(items, id: \.self) { i in
                ListRow(space: space, pointer: pointer, tree: tree, index: i, top: top, total: total,
                        showFolder: showFolder)
            }
        }
    }
}

private struct ListRow: View {
    @ObservedObject var space: SpaceModel
    var pointer: MapPointer
    var tree: DiskTree
    var index: Int
    var top: Int64
    var total: Int64?
    var showFolder: Bool
    @State private var hovering = false

    var body: some View {
        let node = tree[index]
        let selected = space.selection == index
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(node.kind.color.opacity(node.isSynthetic ? 0.45 : 1))
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if let total, total > 0 {
                    Text(Format.percent(Double(node.size) / Double(total)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(Format.diskBytes(node.size))
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .frame(minWidth: 62, alignment: .trailing)
            }
            .font(.callout)
            FillBar(fraction: min(1, Double(node.size) / Double(top)), tint: node.kind.color.opacity(0.85))
                .frame(height: 8)
            Text(detail(node))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18) : (hovering ? Color.primary.opacity(0.06) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside {
                pointer.hovered = index
            } else if pointer.hovered == index {
                pointer.hovered = nil
            }
        }
        .onTapGesture(count: 2) { space.open(index) }
        .onTapGesture { space.reveal(inMap: index) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: L("Zoom avanti")) { space.open(index) }
    }

    /// Tipo, e per i file in un elenco misto la cartella che li contiene.
    private func detail(_ node: DiskNode) -> String {
        var parts: [String]
        if node.isSynthetic {
            parts = [node.items == 0 ? L("Fuori dalla lettura: spazio di macOS") : L("Piccoli elementi sommati")]
        } else {
            parts = [node.kind.title]
        }
        if node.isDirectory, node.items > 0 { parts.append(L("%d elementi", node.items)) }
        if showFolder, node.parent >= 0, let path = tree.path(of: node.parent) {
            parts.append((path as NSString).abbreviatingWithTildeInPath)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Colori dei tipi

extension FileKind {
    /// Colori distinti tra loro e lontani dalla scala del carico: qui il colore dice il tipo, non un allarme.
    /// Il tipo si legge anche in parole (elenco, legenda, riga di stato): il colore non è mai l'unico segnale.
    var nsColor: NSColor {
        switch self {
        case .apps: NSColor(srgbRed: 0.33, green: 0.55, blue: 0.90, alpha: 1)
        case .documents: NSColor(srgbRed: 0.20, green: 0.66, blue: 0.64, alpha: 1)
        case .media: NSColor(srgbRed: 0.72, green: 0.45, blue: 0.85, alpha: 1)
        case .development: NSColor(srgbRed: 0.93, green: 0.52, blue: 0.25, alpha: 1)
        case .system: NSColor(srgbRed: 0.56, green: 0.57, blue: 0.60, alpha: 1)
        case .caches: NSColor(srgbRed: 0.96, green: 0.78, blue: 0.26, alpha: 1)
        case .other: NSColor(srgbRed: 0.45, green: 0.68, blue: 0.40, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Testo scuro sui colori chiari (cache), bianco sugli altri.
    var inkIsDark: Bool { self == .caches }

}

// MARK: - Quick Look

@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    /// Scritto solo sul main thread; il pannello lo legge da lì.
    nonisolated(unsafe) private var urls: [URL] = []

    /// Apre l'anteprima di un file; se è già aperta sullo stesso file, la chiude (come la barra spaziatrice nel Finder).
    func toggle(_ url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, urls == [url] {
            panel.orderOut(nil)
            return
        }
        urls = [url]
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}
