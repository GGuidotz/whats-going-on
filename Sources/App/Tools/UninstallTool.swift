// Attrezzi › Disinstalla: le app installate, quanto pesano e quando le hai aperte l'ultima volta; per ognuna, cosa
// ha lasciato nella Libreria (AppUninstaller, in Sources/Core). Disinstallare sposta app e avanzi scelti nel Cestino,
// con conferma. Niente gira finché non apri la scheda; chiusa la finestra, l'elenco se ne va.

import AppKit
import SwiftUI

@MainActor
final class UninstallModel: ObservableObject {
    enum Sort: String, CaseIterable, Identifiable {
        case size, lastUsed, name
        var id: String { rawValue }
        var title: String {
            switch self {
            case .size: L("Dimensione")
            case .lastUsed: L("Ultimo uso")
            case .name: L("Nome")
            }
        }
    }

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var loading = false
    @Published private(set) var measuring = false
    @Published var sort: Sort = .size
    @Published var query = ""
    @Published var selection: String? {
        didSet { if selection != oldValue { loadLeftovers() } }
    }
    @Published private(set) var leftovers: [Leftover] = []
    @Published private(set) var leftoversLoading = false
    /// Gli avanzi scelti per il Cestino.
    @Published var chosen = Set<String>()
    @Published var message: String?

    private var generation = 0
    /// Dimensioni già note dalla mappa dello spazio, se l'hai letta: si evita di rimisurare.
    var knownSize: ((String) -> Int64?)?
    /// Byte finiti nel Cestino con una disinstallazione.
    var onFreed: ((Int64) -> Void)?

    var selected: InstalledApp? { apps.first { $0.path == selection } }

    var visible: [InstalledApp] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let list = text.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(text) || ($0.bundleID ?? "").localizedCaseInsensitiveContains(text)
        }
        switch sort {
        case .name: return list
        case .size: return list.sorted { ($0.size ?? -1) > ($1.size ?? -1) }
        case .lastUsed: return list.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    var totalSize: Int64 { apps.reduce(0) { $0 + ($1.size ?? 0) } }

    /// Elenco, poi le dimensioni una per una, su una coda a bassa priorità.
    func load() {
        guard !loading else { return }
        generation += 1
        let current = generation
        loading = true
        let known = knownSize
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let list = AppUninstaller.list()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    self.apps = list.map { app in
                        var app = app
                        app.size = known?(app.path)
                        return app
                    }
                    self.loading = false
                    self.measure(current)
                }
            }
        }
    }

    private func measure(_ current: Int) {
        let missing = apps.filter { $0.size == nil }.map(\.path)
        guard !missing.isEmpty else { return }
        measuring = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for path in missing {
                let stale = { DispatchQueue.main.sync { MainActor.assumeIsolated { self?.generation != current } } }
                if stale() { return }
                let size = AppUninstaller.allocatedSize(path, cancelled: stale)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.generation == current,
                              let i = self.apps.firstIndex(where: { $0.path == path }) else { return }
                        self.apps[i].size = size
                    }
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    self.measuring = false
                }
            }
        }
    }

    func cancel() {
        generation += 1
        loading = false
        measuring = false
    }

    private func loadLeftovers() {
        leftovers = []
        chosen = []
        message = nil
        guard let app = selected else { return }
        leftoversLoading = true
        let current = generation
        let others = Set(apps.compactMap(\.bundleID))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = AppUninstaller.leftovers(for: app, others: others)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == current, self.selection == app.path else { return }
                    self.leftovers = found
                    self.chosen = Set(found.filter { $0.match != .name && !$0.needsAdmin }.map(\.path))
                    self.leftoversLoading = false
                }
            }
        }
    }

    /// L'app è aperta: va chiusa prima.
    func running(_ app: InstalledApp) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.path == app.path || (app.bundleID != nil && $0.bundleIdentifier == app.bundleID)
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func uninstall(_ app: InstalledApp) {
        guard app.isRemovable else { return }
        if let running = running(app) {
            guard ToolsAlert.confirm(title: L("%@ è aperta", app.name),
                                     message: L("Va chiusa prima di disinstallarla. Se ha documenti non salvati, te lo chiede."),
                                     button: L("Chiudi %@", app.name)) else { return }
            running.terminate()
            message = L("Ho chiesto a %@ di chiudersi: quando è chiusa, premi di nuovo Disinstalla.", app.name)
            return
        }
        let extras = leftovers.filter { chosen.contains($0.path) && !$0.needsAdmin }
        let total = (app.size ?? 0) + extras.reduce(0) { $0 + $1.size }
        var lines = ["• " + app.name + ".app"]
        lines += extras.prefix(6).map { "• " + $0.name }
        if extras.count > 6 { lines.append(L("e altri %d", extras.count - 6)) }
        guard ToolsAlert.confirm(
            title: L("Disinstallare %@?", app.name),
            message: lines.joined(separator: "\n") + "\n\n"
                + L("Tutto va nel Cestino: liberi %@ quando lo svuoti, e fino ad allora puoi rimettere ogni cosa dov'era.",
                    Format.diskBytes(total)),
            button: L("Sposta nel Cestino")) else { return }

        diag(.app, "uninstall \(app.bundleID ?? app.name) with \(extras.count) leftovers")
        // L'app con NSWorkspace: se è di root (installata da un pacchetto), macOS chiede la password come il Finder.
        NSWorkspace.shared.recycle([URL(fileURLWithPath: app.path)]) { [weak self] _, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.didRecycle(app, extras: extras, failed: error != nil) }
            }
        }
    }

    private func didRecycle(_ app: InstalledApp, extras: [Leftover], failed: Bool) {
        if failed {
            message = L("%@ non è andata nel Cestino. Prova dal Finder: te la mostro.", app.name)
            reveal(app.path)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var moved: Int64 = app.size ?? 0
            var notMoved: [String] = []
            for item in extras {
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                    moved += item.size
                } catch {
                    notMoved.append(item.name)
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.apps.removeAll { $0.path == app.path }
                    self.selection = nil
                    var text = L("%@ è nel Cestino, con %d avanzi: %@ in tutto.", app.name, extras.count - notMoved.count,
                                 Format.diskBytes(moved))
                    if !notMoved.isEmpty {
                        text += " " + L("Non spostati: %@. Prova dal Finder.", notMoved.prefix(4).joined(separator: ", "))
                    }
                    self.message = text
                    self.onFreed?(moved)
                    diag(.app, "uninstalled \(app.bundleID ?? app.name), \(notMoved.count) leftovers failed")
                }
            }
        }
    }
}

struct UninstallView: View {
    @ObservedObject var model: UninstallModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header
                TextField(L("Cerca un'app"), text: $model.query)
                    .textFieldStyle(.roundedBorder)
                if model.loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let app = model.selected {
                        AppDetailCard(model: model, app: app)
                    } else {
                        Text(L("Scegli un'app: qui vedi cosa ha lasciato sul Mac e la togli con tutto il resto."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentCard(padding: 10)
                    }
                }
                .padding(14)
            }
            .frame(width: 330)
        }
        .onAppear { if model.apps.isEmpty { model.load() } }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("%d app", model.apps.count))
                    .font(.title2.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
                HStack(spacing: 6) {
                    Text(model.measuring ? L("%@ finora, sto misurando…", Format.diskBytes(model.totalSize))
                                         : L("%@ in tutto", Format.diskBytes(model.totalSize)))
                        .monospacedDigit()
                    if model.measuring { ProgressView().controlSize(.mini) }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Picker(L("Ordina per"), selection: $model.sort) {
                ForEach(UninstallModel.Sort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
        .padding(.top, 4)
    }

    private var list: some View {
        let apps = model.visible
        let largest = apps.compactMap(\.size).max() ?? 1
        return ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(apps) { app in
                    UninstallRow(app: app, largest: largest, selected: model.selection == app.path)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selection = app.path }
                        .accessibilityAddTraits(model.selection == app.path ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }
}

private struct UninstallRow: View {
    var app: InstalledApp
    var largest: Int64
    var selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.name).lineLimit(1)
                    if app.isApple {
                        Text(L("di Apple")).font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 6)
                    Text(UninstallFormat.lastUsed(app.lastUsed))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(app.size.map(Format.diskBytes) ?? "…")
                        .monospacedDigit().fontWeight(.semibold)
                        .frame(minWidth: 70, alignment: .trailing)
                }
                FillBar(fraction: app.size.map { min(1, Double($0) / Double(max(1, largest))) } ?? 0,
                        tint: Color.accentColor.opacity(0.7))
                    .frame(height: 6)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

enum UninstallFormat {
    /// "aperta oggi", "3 mesi fa", "mai aperta" (o non lo sa Spotlight).
    static func lastUsed(_ date: Date?) -> String {
        guard let date else { return L("uso sconosciuto") }
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return L("usata oggi")
        case 1: return L("usata ieri")
        case ..<30: return L("usata %d giorni fa", days)
        case ..<365: return days / 30 == 1 ? L("usata 1 mese fa") : L("usata %d mesi fa", days / 30)
        default: return days / 365 == 1 ? L("usata 1 anno fa") : L("usata %d anni fa", days / 365)
        }
    }
}

private struct AppDetailCard: View {
    @ObservedObject var model: UninstallModel
    var app: InstalledApp

    private var extrasSize: Int64 {
        model.leftovers.filter { model.chosen.contains($0.path) && !$0.needsAdmin }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable().frame(width: 40, height: 40).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.headline).lineLimit(2)
                        if let version = app.version {
                            Text(L("Versione %@", version)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                DetailLine(label: L("App"), value: app.size.map(Format.diskBytes) ?? "…")
                DetailLine(label: L("Avanzi scelti"), value: Format.diskBytes(extrasSize))
                DetailLine(label: L("Ultimo uso"), value: UninstallFormat.lastUsed(app.lastUsed))
                if let id = app.bundleID {
                    Text(id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack {
                    Button(L("Mostra nel Finder")) { model.reveal(app.path) }
                        .glassButton()
                    if app.isRemovable {
                        Button(L("Disinstalla")) { model.uninstall(app) }
                            .glassProminentButton()
                            .disabled(model.leftoversLoading)
                    }
                }
                .controlSize(.small)
                .padding(.top, 2)
                if app.isApple {
                    Text(L("Le app di Apple fanno parte di macOS o si tolgono dall'App Store: da qui non si disinstallano."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentCard(padding: 10)

            if !app.isApple {
                ToolSection(title: L("Cosa ha lasciato sul Mac"), symbol: "tray.full") {
                    leftoversList
                }
            }
        }
    }

    @ViewBuilder private var leftoversList: some View {
        if model.leftoversLoading {
            ProgressView().controlSize(.small)
        } else if model.leftovers.isEmpty {
            Text(L("Niente nella Libreria: basta togliere l'app."))
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.leftovers) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if item.needsAdmin {
                            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 16)
                                .help(L("Fuori dalla tua cartella: si toglie dal Finder, con la password."))
                                .accessibilityLabel(L("Serve la password"))
                        } else {
                            Toggle(isOn: Binding(
                                get: { model.chosen.contains(item.path) },
                                set: { if $0 { model.chosen.insert(item.path) } else { model.chosen.remove(item.path) } })) {
                                EmptyView()
                            }
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .accessibilityLabel(item.name)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).lineLimit(1).truncationMode(.middle).help(item.path)
                            Text(item.match == .name ? L("%@ · trovato per nome, controlla", item.place) : item.place)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(Format.diskBytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                        Button { model.reveal(item.path) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                            .help(L("Mostra nel Finder"))
                            .accessibilityLabel(L("Mostra %@ nel Finder", item.name))
                    }
                    .font(.caption)
                }
            }
            .contentCard(padding: 10)
            Text(L("Scelti già quelli che portano il nome esatto dell'app. Quelli trovati per nome possono essere di un'altra app dello stesso produttore: guardali prima."))
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
