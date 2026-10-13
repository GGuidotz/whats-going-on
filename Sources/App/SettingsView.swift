// Impostazioni (⌘,): cinque schede sotto una barra di vetro che galleggia. Solo ciò che si cambia di rado
// (settings.md › Desktop), più aggiornamenti e feedback, come in Nod.

import AppKit
import SwiftUI

struct SettingsView: View {
    static let size = CGSize(width: 600, height: 660)

    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences

    init(model: AppModel) {
        self.model = model
        prefs = model.prefs
    }

    var body: some View {
        Group {
            switch model.settingsTab {
            case .general: GeneralSettings(prefs: prefs)
            case .menuBar: MenuBarSettings(prefs: prefs, monitor: model.monitor)
            case .alerts: AlertsSettings(prefs: prefs, delivery: model.delivery)
            case .updates: UpdatesSettings(updater: model.updater, prefs: prefs)
            case .feedback: FeedbackSettings(model: model)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsTabBar(selection: $model.settingsTab)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .id(prefs.language)   // cambio di lingua: ridisegna tutto subito
    }
}

/// Il testo sotto una sezione.
private struct Footnote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Generale

private struct GeneralSettings: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle(L("Apri all'accesso"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        loginError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                if let loginError { Footnote(loginError) }
                Picker(L("Aggiorna ogni"), selection: $prefs.interval) {
                    Text(L("%d s", 1)).tag(1.0)
                    Text(L("%d s", 2)).tag(2.0)
                    Text(L("%d s", 5)).tag(5.0)
                }
                Picker(L("Lingua"), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Footnote(L("A pannello aperto i dati si aggiornano ogni secondo."))
            }

            Section {
                Toggle(L("Modalità avanzata"), isOn: $prefs.advanced)
            } footer: {
                Footnote(L("Aggiunge la GPU, il carico di ogni core, tutti i sensori di temperatura e più app nei dettagli."))
            }
        }
    }
}

// MARK: - Barra dei menu

private struct MenuBarSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        Form {
            Section {
                MenuBarPreview(monitor: monitor, prefs: prefs)
                    .frame(maxWidth: .infinity)
                Picker(L("Stile"), selection: $prefs.style) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                SpacingSlider(title: L("Spazio tra le voci"), value: $prefs.itemSpacing, range: 0...12, step: 1)
                SpacingSlider(title: L("Spazio tra sigla e valore"), value: $prefs.labelGap, range: 0...4, step: 0.5)
            } header: {
                Text(L("Anteprima"))
            } footer: {
                Footnote(L("Il colore dei valori va dal verde al rosso con il carico; upload e download hanno colori propri. La sigla accanto, una lettera sotto l'altra, dice cosa stai guardando. Con gli spazi a zero la barra è la più stretta possibile."))
            }

            Section {
                ForEach(prefs.moduleOrder) { module in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { prefs.enabledModules.contains(module) },
                            set: { if $0 { prefs.enabledModules.insert(module) } else { prefs.enabledModules.remove(module) } }
                        )) {
                            Label(module.title, systemImage: module.symbol)
                        }
                        Spacer()
                        Button { prefs.move(module, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(prefs.moduleOrder.first == module)
                            .accessibilityLabel(L("Sposta %@ a sinistra", module.title))
                        Button { prefs.move(module, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(prefs.moduleOrder.last == module)
                            .accessibilityLabel(L("Sposta %@ a destra", module.title))
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text(L("Cosa mostrare"))
            } footer: {
                Footnote(L("L'ordine dall'alto in basso è quello da sinistra a destra nella barra. Temperatura, GPU e consumo compaiono solo se questo Mac li fornisce."))
            }
        }
    }
}

/// Uno spazio della barra in punti, con il valore scritto accanto.
private struct SpacingSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 180)
                    .accessibilityLabel(title)
                    .accessibilityValue(L("%@ punti", Format.number(value, digits: step < 1 ? 1 : 0)))
                Text(L("%@ pt", Format.number(value, digits: step < 1 ? 1 : 0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

/// La barra com'è adesso, su una barra chiara e su una scura.
private struct MenuBarPreview: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var prefs: Preferences

    var body: some View {
        let entries = MenuBarRenderer.entries(prefs.visibleModules, snapshot: monitor.snapshot, history: monitor.history,
                                              graphs: prefs.style == .graphs)
        HStack(spacing: 10) {
            strip(entries, dark: false)
            strip(entries, dark: true)
        }
        .padding(.vertical, 4)
    }

    private func strip(_ entries: [MenuBarEntry], dark: Bool) -> some View {
        Group {
            if entries.isEmpty {
                Image(systemName: "waveform.path.ecg").foregroundStyle(dark ? Color.white : Color.black)
            } else {
                Image(nsImage: MenuBarRenderer.image(entries, dark: dark, layout: prefs.menuBarLayout))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(dark ? Color(white: 0.13) : Color(white: 0.94)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dark ? L("Anteprima su barra scura") : L("Anteprima su barra chiara"))
        .accessibilityValue(MenuBarRenderer.spokenLabel(entries))
    }
}

// MARK: - Avvisi

private struct AlertsSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var delivery: AlertDelivery

    var body: some View {
        Form {
            Section {
                Picker(L("Mostra gli avvisi in"), selection: $prefs.alertDestination) {
                    ForEach(AlertDestination.allCases) { Text($0.title).tag($0) }
                }
                if prefs.alertDestination == .cocaine {
                    let status = cocaineStatus
                    Label {
                        Text(status.text).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: status.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(status.ok ? Palette.calm : Color.orange)
                    }
                    .font(.callout)
                }
                HStack {
                    Button(L("Invia un avviso di prova")) { delivery.sendTest(to: prefs.alertDestination) }
                    if prefs.alertDestination == .cocaine, delivery.cocaineRunning {
                        Button(L("Prova da lontano")) { delivery.sendTestWhenAway(to: prefs.alertDestination) }
                            .disabled(delivery.awayTestPending)
                            .help(L("Parte tra 25 secondi: lascia il Mac e guarda l'isola di Cocaine."))
                    }
                }
                if let last = delivery.lastDelivered { Footnote(last) }
            } footer: {
                if prefs.alertDestination == .cocaine {
                    Footnote(L("Ogni avviso finisce comunque negli avvisi recenti di Cocaine. Quando Cocaine non lo mostrerebbe, arriva anche come notifica di macOS."))
                }
            }

            Section {
                ForEach(AlertKind.allCases) { kind in
                    AlertRuleRow(kind: kind, rule: Binding(get: { prefs.alerts[kind] }, set: { prefs.alerts[kind] = $0 }))
                }
            } header: {
                Text(L("Quando avvisare"))
            }

            Section {
                Picker(L("Tra due avvisi uguali aspetta"), selection: $prefs.alerts.cooldownMinutes) {
                    ForEach([5.0, 15, 30, 60], id: \.self) { Text(L("%d min", Int($0))).tag($0) }
                }
            } footer: {
                Footnote(L("Un avviso torna solo dopo che il valore è sceso sotto la soglia, e mai prima di questa attesa."))
            }
        }
        .onAppear { delivery.refreshCocaine() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            delivery.refreshCocaine()   // tornando dalle impostazioni di Cocaine, lo stato è già aggiornato
        }
    }

    private var cocaineStatus: (text: String, ok: Bool) {
        if !delivery.cocaineInstalled { return (L("Cocaine non è installato: gli avvisi arrivano come notifiche."), false) }
        if !delivery.cocaineRunning { return (L("Cocaine è chiuso: finché non lo apri gli avvisi arrivano come notifiche."), false) }
        let c = delivery.cocaine
        if let until = c.pausedUntil {
            return (L("In Cocaine gli avvisi sono in pausa fino alle %@: intanto arrivano come notifiche.",
                      until.formatted(date: .omitted, time: .shortened)), false)
        }
        if !c.flash {
            return (L("In Cocaine il lampeggio è spento (Avvisi AI › Come › Lampeggio): gli avvisi arrivano come notifiche."), false)
        }
        if c.whenPresent { return (L("Cocaine è aperto e mostra gli avvisi nell'isola anche mentre usi il Mac."), true) }
        return (L("Cocaine mostra gli avvisi solo quando sei lontano dal Mac da almeno 20 secondi: mentre lo usi arrivano come notifiche. Per vederli sempre nell'isola, in Cocaine accendi Avvisi AI › Quando › Anche al Mac."), true)
    }
}

private struct AlertRuleRow: View {
    var kind: AlertKind
    @Binding var rule: AlertRule

    private static let durations: [Double] = [0, 30, 60, 120, 300, 600]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(kind.title, isOn: $rule.enabled)
            if rule.enabled {
                HStack(spacing: 16) {
                    if let range = range {
                        Stepper(value: $rule.threshold, in: range.bounds, step: range.step) {
                            Text(thresholdText).monospacedDigit()
                        }
                    } else {
                        Text(L("Quando la pressione è critica")).foregroundStyle(.secondary)
                    }
                    if kind != .disk {
                        Picker(L("per"), selection: $rule.duration) {
                            ForEach(Self.durations, id: \.self) { Text(durationTitle($0)).tag($0) }
                        }
                        .fixedSize()
                    }
                }
                .font(.callout)
                .padding(.leading, 20)
            }
        }
    }

    private var range: (bounds: ClosedRange<Double>, step: Double)? {
        switch kind {
        case .cpu: (50...100, 5)
        case .disk: (5...30, 1)
        case .temperature: (70...105, 1)
        case .process: (50...800, 25)
        case .memory: nil
        }
    }

    private var thresholdText: String {
        let v = Int(rule.threshold)
        switch kind {
        case .cpu: return L("Sopra il %d%%", v)
        case .disk: return L("Meno del %d%% libero", v)
        case .temperature: return L("Sopra %d°", v)
        case .process: return L("Un'app sopra il %d%% (%@ core)", v, Format.number(rule.threshold / 100, digits: 1))
        case .memory: return ""
        }
    }

    private func durationTitle(_ seconds: Double) -> String {
        if seconds == 0 { return L("subito") }
        return seconds >= 60 ? L("%d min", Int(seconds / 60)) : L("%d s", Int(seconds))
    }
}

// MARK: - Aggiornamenti

private struct UpdatesSettings: View {
    @ObservedObject var updater: Updater
    @ObservedObject var prefs: Preferences
    private let current = Changelog.load().first

    var body: some View {
        Form {
            Section {
                Toggle(L("Controlla automaticamente (ogni 6 ore)"), isOn: $prefs.autoCheckUpdates)
                LabeledContent(L("Versione installata"), value: updater.currentVersion)
                LabeledContent(L("Ultimo controllo")) {
                    if let last = updater.lastCheck { Text(last, style: .relative) } else { Text(L("Mai")) }
                }
                HStack {
                    Button(L("Controlla ora")) { Task { await updater.check() } }
                        .disabled(updater.state == .checking)
                    UpdateStateText(updater: updater)
                }
            }

            if updater.isUpdateAvailable {
                Section { UpdateCard(updater: updater) }
            }

            if let current {
                Section {
                    ChangelogList(entries: [current])
                } header: {
                    Text(L("Novità di questa versione"))
                }
            }
        }
    }
}

private struct UpdateStateText: View {
    @ObservedObject var updater: Updater

    var body: some View {
        switch updater.state {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate:
            Label(L("What's Going On è aggiornato."), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.calm)
        case .available(let version):
            Label(L("Disponibile la versione %@", version), systemImage: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
        case .failed(let why):
            Text(why).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Le novità della nuova versione e il comando per aggiornare.
private struct UpdateCard: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .available(let version) = updater.state {
                Label(L("Disponibile What's Going On %@", version), systemImage: "arrow.down.circle.fill")
                    .font(.headline)
            }
            if !updater.news.isEmpty { ChangelogList(entries: updater.news) }
            Text(L("Per aggiornare, esegui nel Terminale:")).foregroundStyle(.secondary)
            Text(updater.command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
            HStack {
                Button(L("Copia comando")) { updater.copyCommand() }
                Button(L("Aggiorna nel Terminale")) { updater.runInTerminal() }
                    .glassProminentButton()
            }
            if let error = updater.terminalError {
                Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Feedback

private struct FeedbackSettings: View {
    @ObservedObject var model: AppModel
    @State private var status: String?
    @State private var showReport = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("What's Going On").font(.title2.weight(.semibold)).fontDesign(.rounded)
                        Text(L("Versione %@", "\(SystemInfo.version) (\(SystemInfo.build))")).foregroundStyle(.secondary)
                        Text(L("Cosa succede nel tuo Mac, in una frase.")).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                FeedbackButton(symbol: "ladybug", title: L("Segnala un problema"),
                               detail: L("Su GitHub, con versione, macOS e modello del Mac già scritti.")) {
                    Feedback.openIssue(.problem)
                }
                FeedbackButton(symbol: "lightbulb", title: L("Suggerisci un'idea"),
                               detail: L("Una misura che manca, un avviso utile, un modo migliore di mostrare qualcosa.")) {
                    Feedback.openIssue(.idea)
                }
                FeedbackButton(symbol: "envelope", title: L("Scrivi un'email"),
                               detail: Developer.email) {
                    Feedback.composeEmail()
                }
            } header: {
                Text(L("Feedback"))
            } footer: {
                Footnote(L("GitHub è il canale preferito: le segnalazioni sono pubbliche, quindi non scrivere dati personali. Per qualcosa di privato usa l'email."))
            }

            Section {
                HStack {
                    Button(L("Copia report")) {
                        Feedback.copyReport(model: model)
                        status = L("Report copiato: incollalo nella segnalazione.")
                    }
                    Button(L("Salva…")) { status = Feedback.saveReport(model: model) }
                    Spacer()
                    Button(showReport ? L("Nascondi") : L("Mostra")) { showReport.toggle() }
                }
                if let status { Footnote(status) }
                if showReport {
                    ScrollView {
                        Text(DiagnosticsReport.make(model: model))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                }
            } header: {
                Text(L("Diagnostica"))
            } footer: {
                Footnote(L("Il report dice versione, Mac, quali letture funzionano, le tue scelte e gli ultimi avvisi. Niente nomi di app, file o indirizzi."))
            }

            Section {
                DeveloperLinks()
                Footnote(L("Progetto indipendente, non affiliato a Cocaine."))
            }
        }
    }
}

private struct FeedbackButton: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}
