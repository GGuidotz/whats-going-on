// Attrezzi › Avvio: cosa parte da solo (LaunchAgents e LaunchDaemons) e cosa è rimasto di app che non ci sono più
// (StartupScanner, in Sources/Core). Si legge quando apri la scheda. Azioni solo sugli agenti orfani del tuo utente:
// Disattiva (launchctl, reversibile) e Sposta nel Cestino, entrambe con conferma. Quelli in /Library chiedono la
// password di amministratore: qui si mostrano nel Finder e basta.

import AppKit
import SwiftUI

struct StartupView: View {
    @ObservedObject var model: AppModel
    @State private var onlyOrphans = false
    @State private var selection: String?
    @State private var message: String?

    private var items: [StartupItem] {
        onlyOrphans ? model.startupItems.filter { $0.orphan != nil } : model.startupItems
    }

    private var selected: StartupItem? { model.startupItems.first { $0.id == selection } }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(headline)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentCard(padding: 12)
                HStack {
                    Toggle(L("Solo gli orfani"), isOn: $onlyOrphans)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button {
                        model.refreshStartup(withState: true)
                    } label: {
                        Label(L("Aggiorna"), systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }
                List(selection: $selection) {
                    ForEach(StartupItem.Domain.allCases, id: \.self) { domain in
                        let group = items.filter { $0.domain == domain }
                        if !group.isEmpty {
                            Section(domain.title) {
                                ForEach(group) { StartupRow(item: $0).tag($0.id) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let item = selected {
                        ToolSection(title: item.displayName, symbol: "doc.badge.gearshape") {
                            details(item)
                        }
                    } else {
                        ToolSection(title: L("Cosa sono"), symbol: "info.circle") {
                            Text(L("Programmi che macOS avvia da solo: aggiornatori, aiutanti, servizi. Un orfano appartiene a un'app che non c'è più (di solito tolta trascinandola nel Cestino): macOS prova ancora ad avviarlo. Scegline uno per i dettagli."))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ToolSection(title: L("Elementi login"), symbol: "person.crop.circle.badge.checkmark") {
                        Text(L("Le app che si aprono all'accesso e i permessi \"in background\" si gestiscono in Impostazioni di Sistema: leggerli da qui richiede la password di amministratore."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L("Apri Elementi login")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .glassButton()
                        .controlSize(.small)
                    }
                }
                .padding(14)
            }
            .frame(width: 330)
        }
        .onAppear { model.refreshStartup(withState: true) }
    }

    private var headline: String {
        let r = StartupReport(model.startupItems)
        if model.startupItems.isEmpty { return L("Sto leggendo cosa parte da solo…") }
        if r.orphans == 0 { return L("%d elementi di avvio, nessun orfano: tutto appartiene ad app installate.", r.total) }
        return r.orphans == 1
            ? L("%d elementi di avvio, 1 orfano: appartiene a un'app che non c'è più.", r.total)
            : L("%d elementi di avvio, %d orfani: appartengono ad app che non ci sono più.", r.total, r.orphans)
    }

    @ViewBuilder
    private func details(_ item: StartupItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let orphan = item.orphan {
                Label(orphan.reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DetailLine(label: L("Etichetta"), value: item.label)
            if let program = item.program {
                DetailLine(label: L("Programma"), value: (program as NSString).abbreviatingWithTildeInPath)
            }
            DetailLine(label: L("Parte"), value: item.keepAlive ? L("sempre, e riparte se si chiude")
                       : (item.runAtLoad ? L("all'avvio o all'accesso") : L("quando serve")))
            DetailLine(label: L("Stato"), value: item.statusText)
            DetailLine(label: L("File"), value: (item.url.path as NSString).abbreviatingWithTildeInPath)

            HStack(spacing: 8) {
                Button(L("Mostra nel Finder")) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                if item.isActionable {
                    if item.disabled {
                        Button(L("Riattiva")) { act(item, enable: true) }
                    } else {
                        Button(L("Disattiva…")) { act(item, enable: false) }
                    }
                    Button(L("Sposta nel Cestino…")) { trash(item) }
                }
            }
            .controlSize(.small)
            .padding(.top, 6)

            if item.orphan != nil, !item.isActionable {
                Text(L("Sta in /Library: per toglierlo servono i privilegi di amministratore. Mostralo nel Finder e trascinalo nel Cestino, macOS chiederà la password."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func act(_ item: StartupItem, enable: Bool) {
        do {
            if enable {
                try StartupScanner.enable(item)
                message = L("%@ è di nuovo attivo: riparte al prossimo accesso.", item.label)
            } else {
                guard ToolsAlert.confirm(
                    title: L("Disattivare %@?", item.label),
                    message: L("macOS lo ferma e non lo avvia più, nemmeno al prossimo accesso. Il file resta dov'è: puoi riattivarlo da qui."),
                    button: L("Disattiva")) else { return }
                try StartupScanner.disable(item)
                message = L("%@ è disattivato.", item.label)
            }
        } catch {
            message = L("Non ci sono riuscito: %@", String(describing: error))
        }
        model.refreshStartup(withState: true)
    }

    private func trash(_ item: StartupItem) {
        guard ToolsAlert.confirm(
            title: L("Spostare %@ nel Cestino?", item.url.lastPathComponent),
            message: L("macOS lo ferma e il file va nel Cestino: puoi rimetterlo a posto da lì finché non lo svuoti."),
            button: L("Sposta nel Cestino")) else { return }
        do {
            try StartupScanner.moveToTrash(item)
            message = L("%@ è nel Cestino.", item.url.lastPathComponent)
            selection = nil
        } catch {
            message = L("Non ci sono riuscito: %@", String(describing: error))
        }
        model.refreshStartup(withState: true)
    }
}

private struct StartupRow: View {
    var item: StartupItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.orphan != nil ? "exclamationmark.triangle.fill" : "gearshape")
                .foregroundStyle(item.orphan != nil ? Color.orange : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).lineLimit(1)
                Text(item.orphan != nil ? L("Orfano") + " · " + item.statusText : item.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension StartupItem {
    var statusText: String {
        if disabled { return L("disattivato") }
        switch state {
        case .running: return L("in esecuzione")
        case .loaded(let exit): return exit == 0 ? L("pronto") : L("fermo, ultima uscita con errore %d", Int(exit))
        case .notLoaded: return L("non caricato")
        case .unknown: return domain == .daemon ? L("di sistema") : L("stato sconosciuto")
        }
    }
}
