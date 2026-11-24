// Impostazioni (⌘,): cinque schede, con la barra a capsula di Sguardo che galleggia in fondo. Solo ciò che si cambia di rado
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
        ZStack(alignment: .bottom) {
            Group {
                switch model.settingsTab {
                case .general: GeneralSettings(model: model, prefs: prefs, monitor: model.monitor)
                case .menuBar: MenuBarSettings(prefs: prefs, monitor: model.monitor)
                case .alerts: AlertsSettings(prefs: prefs, delivery: model.delivery)
                case .updates: UpdatesSettings(updater: model.updater, prefs: prefs)
                case .feedback: FeedbackSettings(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // La barra delle schede galleggia in fondo: le righe ci scorrono sotto (SGPage lascia lo spazio).
            SettingsTabBar(selection: $model.settingsTab)
                .padding(.bottom, SG.Size.tabBarBottomInset)
        }
        // In alto, sotto i semafori della finestra, il contenuto sfuma invece di tagliarsi di netto.
        .overlay(alignment: .top) { SGProgressiveBlur() }
        .frame(width: Self.size.width, height: Self.size.height)
        // La barra del titolo è trasparente e la vista occupa tutta la finestra: senza questo la zona sicura in alto
        // spinge giù tutto e la barra delle schede finisce sul bordo inferiore.
        .ignoresSafeArea()
        .sguardoAccent(default: .whatsGoingOn)
        .id(prefs.language)   // cambio di lingua: ridisegna tutto subito
    }
}

// MARK: - Generale

private struct GeneralSettings: View {
    var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var monitor: SystemMonitor
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?
    @State private var fullDiskAccess = FullDiskAccess.granted

    var body: some View {
        SGPage {
            SGSection {
                SGToggleRow(L("Apri all'accesso"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        loginError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                if let loginError {
                    SGRowBlock { SGFootnote(loginError) }
                }
                SGDivider()
                SGMenuRow(L("Aggiorna ogni"), selection: $prefs.interval,
                          options: [1, 2, 5].map { (value: Double($0), title: L("%d s", $0)) })
                SGDivider()
                SGMenuRow(L("Lingua"), selection: $prefs.language,
                          options: AppLanguage.allCases.map { (value: $0, title: $0.title) })
                SGDivider()
                SGAccentRow(L("Colore d'accento"),
                            options: (app: L("Colore dell'app"), system: L("Colore di sistema"), custom: L("Personalizzato")),
                            appDefault: .whatsGoingOn)
            } footer: {
                SGFootnote(L("A pannello aperto i dati si aggiornano ogni secondo."))
            }

            SGSection {
                SGToggleRow(L("Modalità avanzata"), isOn: $prefs.advanced)
            } footer: {
                SGFootnote(L("Aggiunge la GPU, il carico di ogni core, tutti i sensori di temperatura e più app nei dettagli."))
            }

            SGSection(L("Attrezzi")) {
                SGLabeledRow {
                    Text(L("Accesso completo al disco"))
                } trailing: {
                    if fullDiskAccess {
                        Label(L("Concesso"), systemImage: "checkmark.circle.fill")
                            .font(SG.Font.body)
                            .foregroundStyle(Palette.calm)
                    } else {
                        Button(L("Apri Impostazioni")) { FullDiskAccess.openSettings() }
                            .buttonStyle(.sgSecondary)
                    }
                }
                SGDivider()
                SGToggleRow(L("Consigli di Apple Intelligence (sperimentale)"), isOn: $prefs.intelligence)
                SGDivider()
                SGRowBlock {
                    Button(L("Apri gli attrezzi")) { model.showTools(.space) }
                        .buttonStyle(.sgSecondary)
                }
            } footer: {
                SGFootnote(L("Gli attrezzi (cosa occupa spazio, memoria e CPU, Mole) lavorano solo quando li apri. L'accesso completo al disco serve a vedere Mail, Messaggi, Safari e i backup nella mappa: in Privacy e sicurezza aggiungi What's Going On con +.")
                           + (prefs.intelligence ? " " + (AdviceModel.unavailableReason ?? L("Apple Intelligence è pronta.")) : ""))
            }
            .onAppear { fullDiskAccess = FullDiskAccess.granted }

            HistorySettings(prefs: prefs, monitor: monitor)

            SGSection {
                SGValueRow(L("Consumo di What's Going On"), value: monitor.snapshot.ownUsage.map {
                    L("%@ di CPU · %@", Format.corePercent($0.cpu), Format.bytes($0.memory))
                } ?? "–")
                SGDivider()
                SGRowBlock {
                    Button(L("Rivedi la guida iniziale")) { model.showOnboarding() }
                        .buttonStyle(.sgSecondary)
                }
            } footer: {
                SGFootnote(L("L'obiettivo è restare sotto l'1% di CPU: a pannello chiuso l'app legge solo ciò che mostri nella barra e ciò che serve agli avvisi accesi. Con questa finestra aperta il valore è un po' più alto."))
            }
        }
    }
}

/// La cronologia di 7 giorni: accesa o spenta, quanto copre, cancellala.
private struct HistorySettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        SGSection(L("Cronologia")) {
            SGToggleRow(L("Salva la cronologia sul Mac (7 giorni)"), isOn: $prefs.keepsHistory)
            if prefs.keepsHistory {
                SGDivider()
                SGValueRow(L("Copre")) {
                    if let oldest = monitor.longHistory.oldest {
                        Text(L("dal %@, %d minuti", oldest.formatted(date: .abbreviated, time: .shortened),
                               monitor.longHistory.points.count))
                    } else {
                        Text(L("Ancora vuota: il primo punto arriva tra un minuto"))
                    }
                }
            }
            SGDivider()
            SGRowBlock {
                Button(L("Cancella la cronologia…"), role: .destructive) {
                    let alert = NSAlert()
                    alert.messageText = L("Cancellare la cronologia?")
                    alert.informativeText = L("Si perdono i grafici delle 24 ore e dei 7 giorni, lo swap che cresce e la stima del disco pieno. Le letture riprendono da adesso.")
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L("Cancella"))
                    alert.addButton(withTitle: L("Annulla"))
                    if alert.runModal() == .alertFirstButtonReturn { monitor.clearHistory() }
                }
                .buttonStyle(.sgSecondary)
                .disabled(monitor.longHistory.points.isEmpty)
            }
        } footer: {
            SGFootnote(L("Un punto al minuto con soli numeri: CPU, memoria, swap, spazio libero, temperatura. Niente nomi di app o di file. Sta in ~/Library/Application Support/What's Going On e non esce dal Mac."))
        }
    }
}

// MARK: - Barra dei menu

private struct MenuBarSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        SGPage {
            SGSection(L("Anteprima")) {
                SGRowBlock {
                    MenuBarPreview(monitor: monitor, prefs: prefs)
                        .frame(maxWidth: .infinity)
                }
                SGDivider()
                SGRowBlock {
                    Picker(L("Stile"), selection: $prefs.style) {
                        ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                SGDivider()
                SpacingSlider(title: L("Spazio tra le voci"), value: $prefs.itemSpacing, range: 0...12, step: 1)
                SGDivider()
                SpacingSlider(title: L("Spazio tra sigla e valore"), value: $prefs.labelGap, range: 0...4, step: 0.5)
            } footer: {
                SGFootnote(L("La sigla accanto a ogni valore, una lettera sotto l'altra, dice cosa stai guardando. Con gli spazi a zero la barra è la più stretta possibile."))
            }

            ColorScaleSection(prefs: prefs)

            SGSection(L("Cosa mostrare")) {
                ForEach(Array(prefs.moduleOrder.enumerated()), id: \.element) { index, module in
                    if index > 0 { SGDivider() }
                    SGLabeledRow {
                        Label(module.title, systemImage: module.symbol)
                    } trailing: {
                        HStack(spacing: 4) {
                            Button { prefs.move(module, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(prefs.moduleOrder.first == module)
                                .accessibilityLabel(L("Sposta %@ a sinistra", module.title))
                            Button { prefs.move(module, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(prefs.moduleOrder.last == module)
                                .accessibilityLabel(L("Sposta %@ a destra", module.title))
                            SGToggle(isOn: Binding(
                                get: { prefs.enabledModules.contains(module) },
                                set: { if $0 { prefs.enabledModules.insert(module) } else { prefs.enabledModules.remove(module) } }
                            ))
                            .accessibilityLabel(module.title)
                            .padding(.leading, 8)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(SG.Ink.secondary)
                    }
                }
            } footer: {
                SGFootnote(L("L'ordine dall'alto in basso è quello da sinistra a destra nella barra. Temperatura, GPU e consumo compaiono solo se questo Mac li fornisce."))
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
        SGLabeledRow {
            Text(title)
        } trailing: {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .controlSize(.small)
                    .frame(width: 180)
                    .accessibilityLabel(title)
                    .accessibilityValue(L("%@ punti", Format.number(value, digits: step < 1 ? 1 : 0)))
                Text(L("%@ pt", Format.number(value, digits: step < 1 ? 1 : 0)))
                    .font(SG.Font.value)
                    .foregroundStyle(SG.Ink.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 52, alignment: .trailing)
            }
        }
    }
}

/// La scala dei colori del carico: rosso-verde, oppure tre colori scelti (di partenza verde, bianco, rosso).
private struct ColorScaleSection: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        SGSection(L("Colori")) {
            SGRowBlock {
                Picker(L("Scala"), selection: $prefs.colorScale.kind) {
                    ForEach(ColorScale.Kind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if prefs.colorScale.kind == .threeColors {
                SGDivider()
                stop(L("Carico basso"), \.low)
                SGDivider()
                stop(L("Carico medio"), \.mid)
                SGDivider()
                stop(L("Carico alto"), \.high)
                SGDivider()
                SGRowBlock {
                    Button(L("Torna a verde, bianco e rosso")) {
                        prefs.colorScale = ColorScale(kind: .threeColors)
                    }
                    .buttonStyle(.sgSecondary)
                    .disabled(prefs.colorScale.low == .green && prefs.colorScale.mid == .white && prefs.colorScale.high == .red)
                }
            }
            SGDivider()
            SGRowBlock {
                HStack(spacing: 10) {
                    strip(dark: false)
                    strip(dark: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Anteprima della scala, da carico basso a carico alto"))
            }
        } footer: {
            SGFootnote(L("Il colore segue il carico, il numero resta scritto: il colore non è mai l'unico segnale. Upload e download hanno colori propri. Sulla barra chiara i colori troppo chiari si scuriscono un poco, su quella scura i troppo scuri si schiariscono, per restare leggibili."))
        }
    }

    private func stop(_ title: String, _ key: WritableKeyPath<ColorScale, RGB>) -> some View {
        SGLabeledRow {
            Text(title)
        } trailing: {
            ColorPicker(title, selection: Binding(
                get: { let c = prefs.colorScale[keyPath: key]; return Color(.sRGB, red: c.r, green: c.g, blue: c.b) },
                set: { color in
                    guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
                    prefs.colorScale[keyPath: key] = RGB(r: Double(c.redComponent), g: Double(c.greenComponent),
                                                         b: Double(c.blueComponent))
                }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }

    private func strip(dark: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Palette.scaleGradient(prefs.colorScale, dark: dark))
            .frame(height: 10)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: SG.Radius.tile, style: .continuous)
                .fill(dark ? Color(white: 0.13) : Color(white: 0.94)))
            .overlay(RoundedRectangle(cornerRadius: SG.Radius.tile, style: .continuous)
                .strokeBorder(SG.Fill.rowBorder, lineWidth: SG.Stroke.hairline))
    }
}

/// La barra com'è adesso, su una barra chiara e su una scura.
struct MenuBarPreview: View {
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
                Image(nsImage: MenuBarRenderer.image(entries, dark: dark, layout: prefs.menuBarLayout,
                                                     scale: prefs.colorScale))
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
        SGPage {
            SGSection {
                SGMenuRow(L("Mostra gli avvisi in"), selection: $prefs.alertDestination,
                          options: AlertDestination.allCases.map { (value: $0, title: $0.title) })
                if prefs.alertDestination == .cocaine {
                    let status = cocaineStatus
                    SGDivider()
                    SGRowBlock {
                        Label {
                            Text(status.text).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: status.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(status.ok ? Palette.calm : Color.orange)
                        }
                    }
                }
                SGDivider()
                SGRowBlock {
                    HStack(spacing: 8) {
                        Button(L("Invia un avviso di prova")) { delivery.sendTest(to: prefs.alertDestination) }
                            .buttonStyle(.sgSecondary)
                        if prefs.alertDestination == .cocaine, delivery.cocaineRunning {
                            Button(L("Prova da lontano")) { delivery.sendTestWhenAway(to: prefs.alertDestination) }
                                .buttonStyle(.sgSecondary)
                                .disabled(delivery.awayTestPending)
                                .help(L("Parte tra 25 secondi: lascia il Mac e guarda l'isola di Cocaine."))
                        }
                    }
                }
                if let last = delivery.lastDelivered {
                    SGRowBlock { SGFootnote(last) }
                }
            } footer: {
                if prefs.alertDestination == .cocaine {
                    SGFootnote(L("Ogni avviso finisce comunque negli avvisi recenti di Cocaine. Quando Cocaine non lo mostrerebbe, arriva anche come notifica di macOS."))
                }
            }

            SGSection(L("Quando avvisare")) {
                ForEach(Array(AlertKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { SGDivider() }
                    AlertRuleRow(kind: kind, rule: Binding(get: { prefs.alerts[kind] }, set: { prefs.alerts[kind] = $0 }))
                }
                SGDivider()
                SGMenuRow(L("Leggi la temperatura ogni"), selection: $prefs.temperatureInterval, options: [
                    (value: 10.0, title: L("%d s", 10)), (value: 30.0, title: L("%d s", 30)),
                    (value: 60.0, title: L("%d min", 1)), (value: 120.0, title: L("%d min", 2)),
                ])
            } footer: {
                SGFootnote(L("Processo fuori controllo segue anche i processi di macOS e i servizi in background, uno per uno; App che consuma troppo segue le app. Elementi di avvio orfani, giorni di accensione e calore lieve non avvisano: li trovi nel pannello.") + " " + L("I sensori di temperatura sono la lettura più pesante: a pannello chiuso si leggono solo se la temperatura è nella barra o l'avviso Chip caldo è acceso, e solo ogni tanto. A pannello aperto si aggiornano ogni secondo."))
            }

            SGSection {
                SGMenuRow(L("Tra due avvisi uguali aspetta"), selection: $prefs.alerts.cooldownMinutes,
                          options: [5.0, 15, 30, 60].map { (value: $0, title: L("%d min", Int($0))) })
            } footer: {
                SGFootnote(L("Un avviso torna solo dopo che il valore è sceso sotto la soglia, e mai prima di questa attesa."))
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

/// Un avviso: l'interruttore e, se acceso, la soglia e per quanto deve durare.
private struct AlertRuleRow: View {
    var kind: AlertKind
    @Binding var rule: AlertRule

    private static let durations: [Double] = [0, 30, 60, 120, 300, 600, 1200, 1800]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SGToggleRow(kind.title, isOn: $rule.enabled)
            if rule.enabled {
                HStack(spacing: 12) {
                    if let range = range {
                        Stepper(value: $rule.threshold, in: range.bounds, step: range.step) {
                            Text(thresholdText).monospacedDigit()
                        }
                        .controlSize(.small)
                    } else {
                        Text(L("Quando la pressione è critica")).foregroundStyle(SG.Ink.secondary)
                    }
                    Spacer(minLength: 8)
                    if kind != .disk && kind != .swap {
                        Text(L("per")).foregroundStyle(SG.Ink.secondary)
                        SGPickerPill(durationTitle(rule.duration)) {
                            Picker(L("per"), selection: $rule.duration) {
                                ForEach(Self.durations, id: \.self) { Text(durationTitle($0)).tag($0) }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                    }
                }
                .font(SG.Font.body)
                .padding(.horizontal, SG.Space.rowInset)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .animation(SG.Motion.snappy, value: rule.enabled)
    }

    private var range: (bounds: ClosedRange<Double>, step: Double)? {
        switch kind {
        case .cpu: (50...100, 5)
        case .disk: (5...30, 1)
        case .temperature: (70...105, 1)
        case .process: (50...800, 25)
        case .runaway: (50...400, 10)
        case .swap: (200...4000, 100)
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
        case .runaway: return L("Un processo sopra il %d%%", v)
        case .swap: return L("Più di %d MB in 30 min", v)
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
        SGPage {
            SGSection {
                SGToggleRow(L("Controlla automaticamente (ogni 6 ore)"), isOn: $prefs.autoCheckUpdates)
                SGDivider()
                SGValueRow(L("Versione installata"), value: updater.currentVersion)
                SGDivider()
                SGValueRow(L("Ultimo controllo")) {
                    if let last = updater.lastCheck { Text(last, style: .relative) } else { Text(L("Mai")) }
                }
                SGDivider()
                SGRowBlock {
                    HStack(spacing: 10) {
                        Button(L("Controlla ora")) { Task { await updater.check() } }
                            .buttonStyle(.sgSecondary)
                            .disabled(updater.state == .checking)
                        UpdateStateText(updater: updater)
                    }
                }
            }

            if updater.isUpdateAvailable {
                SGSection { SGRowBlock { UpdateCard(updater: updater) } }
            }

            if let current {
                SGSection(L("Novità di questa versione")) {
                    SGRowBlock { ChangelogList(entries: [current]) }
                    SGDivider()
                    SGRowBlock {
                        Button(L("Mostra la schermata delle novità")) { AppModel.shared.showWhatsNew() }
                            .buttonStyle(.sgSecondary)
                    }
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
            Label(L("Disponibile la versione %@", version), systemImage: "arrow.down.circle.fill").foregroundStyle(.tint)
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
                    .font(SG.Font.bodyEmphasis)
            }
            if !updater.news.isEmpty { ChangelogList(entries: updater.news) }
            Text(L("Per aggiornare, esegui nel Terminale:")).foregroundStyle(SG.Ink.secondary)
            Text(updater.command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SG.Fill.tile, in: RoundedRectangle(cornerRadius: SG.Radius.tile, style: .continuous))
            HStack(spacing: 8) {
                Button(L("Copia comando")) { updater.copyCommand() }
                    .buttonStyle(.sgSecondary)
                Button(L("Aggiorna nel Terminale")) { updater.runInTerminal() }
                    .buttonStyle(.sgPrimary)
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
        SGPage {
            SGSection {
                SGRowBlock {
                    HStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 72, height: 72)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("What's Going On").font(SG.Font.title)
                            Text(L("Versione %@", "\(SystemInfo.version) (\(SystemInfo.build))")).foregroundStyle(SG.Ink.secondary)
                            Text(L("Cosa succede nel tuo Mac, in una frase.")).foregroundStyle(SG.Ink.secondary)
                        }
                    }
                }
            }

            SGSection(L("Feedback")) {
                FeedbackButton(symbol: "ladybug", title: L("Segnala un problema"),
                               detail: L("Su GitHub, con versione, macOS e modello del Mac già scritti.")) {
                    Feedback.openIssue(.problem)
                }
                SGDivider()
                FeedbackButton(symbol: "lightbulb", title: L("Suggerisci un'idea"),
                               detail: L("Una misura che manca, un avviso utile, un modo migliore di mostrare qualcosa.")) {
                    Feedback.openIssue(.idea)
                }
                SGDivider()
                FeedbackButton(symbol: "envelope", title: L("Scrivi un'email"),
                               detail: Developer.email) {
                    Feedback.composeEmail()
                }
            } footer: {
                SGFootnote(L("GitHub è il canale preferito: le segnalazioni sono pubbliche, quindi non scrivere dati personali. Per qualcosa di privato usa l'email."))
            }

            SGSection(L("Diagnostica")) {
                SGRowBlock {
                    HStack(spacing: 8) {
                        Button(L("Copia report")) {
                            Feedback.copyReport(model: model)
                            status = L("Report copiato: incollalo nella segnalazione.")
                        }
                        Button(L("Salva…")) { status = Feedback.saveReport(model: model) }
                        Spacer()
                        Button(showReport ? L("Nascondi") : L("Mostra")) { showReport.toggle() }
                    }
                    .buttonStyle(.sgSecondary)
                }
                if let status {
                    SGRowBlock { SGFootnote(status) }
                }
                if showReport {
                    SGDivider()
                    SGRowBlock {
                        ScrollView {
                            Text(DiagnosticsReport.make(model: model))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                    }
                }
            } footer: {
                SGFootnote(L("Il report dice versione, Mac, quali letture funzionano, le tue scelte e gli ultimi avvisi. Niente nomi di app, file o indirizzi."))
            }

            SGSection {
                SGRowBlock {
                    VStack(alignment: .leading, spacing: 8) {
                        DeveloperLinks()
                        SGFootnote(L("Progetto indipendente, non affiliato a Cocaine."))
                    }
                }
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
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(SG.Font.body).foregroundStyle(SG.Ink.primary)
                    Text(detail).font(SG.Font.caption).foregroundStyle(SG.Ink.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(SG.Ink.tertiary)
            }
            .padding(.horizontal, SG.Space.rowInset)
            .padding(.vertical, 10)
            .frame(minHeight: SG.Size.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}
