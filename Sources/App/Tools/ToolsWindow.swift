// La finestra degli Attrezzi: Spazio (cosa occupa il disco), App (memoria, CPU, energia, disco e rete) e Disinstalla.
// Si apre solo quando la chiami: dal pannello, da un avviso, dal menu della voce nella barra. Chiusa, se ne va tutto: albero del disco, viste,
// consigli. Mole resta nel modello dell'app, così un comando avviato finisce anche a finestra chiusa.

import AppKit
import SwiftUI

enum ToolsTab: String, CaseIterable, Identifiable {
    case space, apps, uninstall
    var id: String { rawValue }

    var title: String {
        switch self {
        case .space: L("Spazio")
        case .apps: L("App")
        case .uninstall: L("Disinstalla")
        }
    }

    var symbol: String {
        switch self {
        case .space: "internaldrive"
        case .apps: "memorychip"
        case .uninstall: "xmark.bin"
        }
    }
}

/// Lo stato della finestra: nasce quando si apre, muore quando si chiude.
@MainActor
final class ToolsState: ObservableObject {
    @Published var tab: ToolsTab = .space
    @Published var measure: AppsView.Measure = .memory
    let space = SpaceModel()
    let spaceAdvice = AdviceModel()
    let appsAdvice = AdviceModel()
    let uninstall = UninstallModel()
    let search = SpotlightSearch()

    init() {
        // Se la mappa dello spazio è già stata letta, le dimensioni delle app si prendono da lì.
        uninstall.knownSize = { [weak space = self.space] path in
            MainActor.assumeIsolated {
                guard let tree = space?.tree, let i = tree.find(path) else { return nil }
                return tree[i].size
            }
        }
        // Anche ciò che va nel Cestino disinstallando conta in "Recuperati finora".
        uninstall.onFreed = { [weak space = self.space] bytes in
            MainActor.assumeIsolated { space?.addFreed(bytes) }
        }
    }
}

@MainActor
final class ToolsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var state: ToolsState?

    func show(model: AppModel, tab: ToolsTab, measure: AppsView.Measure? = nil) {
        let state = self.state ?? ToolsState()
        state.tab = tab
        if let measure { state.measure = measure }
        if window == nil {
            self.state = state
            let w = TranslucentWindow.make(ToolsView(model: model, state: state), size: ToolsView.size, resizable: true)
            w.contentMinSize = ToolsView.minSize
            w.setFrameAutosaveName("WhatsGoingOnTools")
            w.delegate = self
            window = w
        }
        window?.title = L("Attrezzi di What's Going On")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Finestra chiusa: si ferma la lettura del disco e si libera tutto.
    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.state?.space.cancel()
                self?.state?.uninstall.cancel()
                self?.state?.search.stop()
                self?.state?.spaceAdvice.reset()
                self?.state?.appsAdvice.reset()
                AppModel.shared.monitor.needs.liveProcesses = false
                self?.window?.contentViewController = nil
                self?.window = nil
                self?.state = nil
            }
        }
    }
}

struct ToolsView: View {
    static let size = CGSize(width: 1040, height: 700)
    static let minSize = CGSize(width: 820, height: 540)

    var model: AppModel
    @ObservedObject var state: ToolsState
    @ObservedObject var prefs: Preferences

    init(model: AppModel, state: ToolsState) {
        self.model = model
        self.state = state
        prefs = model.prefs
    }

    var body: some View {
        Group {
            switch state.tab {
            case .space:
                SpaceView(space: state.space, mole: model.mole, advice: state.spaceAdvice, prefs: prefs,
                          search: state.search)
            case .apps:
                AppsView(monitor: model.monitor, mole: model.mole, advice: state.appsAdvice, prefs: prefs,
                         measure: $state.measure)
            case .uninstall:
                UninstallView(model: state.uninstall)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ToolsTabBar(selection: $state.tab)
                .padding(.top, 2)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: Self.minSize.width, maxWidth: .infinity, minHeight: Self.minSize.height, maxHeight: .infinity)
        .onAppear { model.monitor.needs.liveProcesses = state.tab == .apps }
        .onChange(of: state.tab) { _, tab in model.monitor.needs.liveProcesses = tab == .apps }
        .id(prefs.language)
    }
}

/// Le schede, nella stessa barra di vetro delle impostazioni. ⌘1, ⌘2, ⌘3.
private struct ToolsTabBar: View {
    @Binding var selection: ToolsTab

    var body: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(ToolsTab.allCases.enumerated()), id: \.element) { index, tab in
                    let selected = selection == tab
                    Button {
                        selection = tab
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .frame(width: 110, height: 30)
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                            .background {
                                if selected {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.08))
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(4)
            .glassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Un riquadro della colonna a destra: titolo con simbolo, poi il contenuto.
struct ToolSection<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

@MainActor
enum ToolsAlert {
    /// Chiede conferma prima di un gesto che cambia qualcosa sul disco o chiude un'app.
    static func confirm(title: String, message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: L("Annulla"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Mole

/// Mole dentro la finestra: anteprima, poi il comando vero (con conferma), e l'uscita riga per riga.
struct MoleBox: View {
    @ObservedObject var runner: MoleRunner
    var command: MoleRunner.Command
    @State private var showOutput = false

    private var busy: Bool { runner.current != nil }
    private var mine: Bool { runner.current?.command == command || runner.last?.run.command == command }
    private var previewDone: Bool {
        runner.last == MoleRunner.Outcome(run: .init(command: command, dryRun: true), succeeded: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if runner.isInstalled {
                HStack(spacing: 8) {
                    Button(L("Anteprima")) { runner.run(command, dryRun: true); showOutput = true }
                        .glassButton()
                        .disabled(busy)
                    Button(command == .clean ? L("Pulisci") : L("Ottimizza")) { runReal() }
                        .glassProminentButton()
                        .disabled(busy || (command == .clean && !previewDone))
                    if busy, runner.current?.command == command {
                        ProgressView().controlSize(.small)
                        Button(L("Interrompi")) { runner.stop() }
                            .buttonStyle(.borderless)
                    }
                }
                .controlSize(.small)
                if command == .clean, !previewDone, !busy {
                    Text(L("Prima l'anteprima: vedi cosa toglierebbe."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                HStack(spacing: 8) {
                    if MoleRunner.brew != nil {
                        Button(L("Installa con Homebrew")) { runner.run(.install, dryRun: false); showOutput = true }
                            .glassButton()
                            .disabled(busy)
                        if runner.current?.command == .install { ProgressView().controlSize(.small) }
                    }
                    Link(L("Cos'è Mole"), destination: URL(string: "https://github.com/tw93/Mole")!)
                        .font(.caption)
                }
                .controlSize(.small)
            }
            if mine || runner.current?.command == .install || runner.last?.run.command == .install {
                if let summary = runner.summary, mine {
                    Text(summary).font(.callout.weight(.semibold)).monospacedDigit()
                }
                if let last = runner.last, runner.current == nil, mine || last.run.command == .install {
                    Text(last.succeeded ? L("Fatto.") : L("Mole si è fermato con un errore: guarda i dettagli."))
                        .font(.caption)
                        .foregroundStyle(last.succeeded ? Color.secondary : Color.orange)
                }
                DisclosureGroup(L("Dettagli"), isExpanded: $showOutput) {
                    output
                }
                .font(.caption)
                if command == .clean, previewDone, FileManager.default.fileExists(atPath: MoleRunner.previewList.path) {
                    Button(L("Apri l'elenco completo")) { NSWorkspace.shared.open(MoleRunner.previewList) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .contentCard(padding: 10)
        .onAppear { runner.refresh() }
    }

    private var explanation: String {
        switch command {
        case .clean:
            L("Toglie cache, log e file temporanei delle app (anche di quelle disinstallate). Cancella per sempre, non nel Cestino: sono cose che si ricreano. Le cache di sistema chiedono la password: per quelle, mo clean nel Terminale.")
        case .optimize:
            L("Manutenzione: cache DNS, Spotlight, anteprime e icone, database di sistema. Non libera memoria: per quella chiudi le app qui a sinistra. Se serve la password, Mole la chiede con una finestra sua.")
        case .install:
            ""
        }
    }

    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(runner.lines.enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(6)
            }
            .frame(height: 170)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .onChange(of: runner.lines.count) { _, count in
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
    }

    private func runReal() {
        let ok: Bool
        switch command {
        case .clean:
            ok = ToolsAlert.confirm(
                title: L("Pulire con Mole?"),
                message: (runner.summary.map { $0 + "\n\n" } ?? "")
                    + L("Mole cancella per sempre cache, log e file temporanei: le app li ricreano quando servono. Chiudi prima le app aperte."),
                button: L("Pulisci"))
        case .optimize:
            ok = ToolsAlert.confirm(
                title: L("Fare la manutenzione con Mole?"),
                message: L("Svuota cache DNS e anteprime, ricostruisce le icone e controlla Spotlight. Per qualche minuto il Mac può essere un po' più lento. Se serve, Mole chiede la password."),
                button: L("Ottimizza"))
        case .install:
            ok = false
        }
        guard ok else { return }
        showOutput = true
        runner.run(command, dryRun: false)
    }
}

// MARK: - Apple Intelligence

struct AdviceBox: View {
    @ObservedObject var advice: AdviceModel
    var ask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = AdviceModel.unavailableReason {
                Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("Consigli scritti dal modello sul Mac, a partire da questi dati. Niente esce dal Mac. È sperimentale: controlla sempre prima di agire."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(advice.state == .idle ? L("Chiedi consigli") : L("Chiedi di nuovo")) { ask() }
                        .glassButton()
                        .controlSize(.small)
                        .disabled(advice.state == .working)
                    if advice.state == .working { ProgressView().controlSize(.small) }
                }
                switch advice.state {
                case .answer(let tips):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                            Label {
                                Text(tip).fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "sparkle").foregroundStyle(.tint)
                            }
                            .font(.callout)
                        }
                    }
                case .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                case .idle, .working:
                    EmptyView()
                }
            }
        }
        .contentCard(padding: 10)
    }
}
