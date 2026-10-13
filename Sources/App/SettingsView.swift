// Impostazioni (⌘,): finestra standard con tre pannelli. Solo ciò che si cambia di rado (settings.md › Desktop).

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    var monitor: SystemMonitor
    var delivery: AlertDelivery

    var body: some View {
        TabView {
            GeneralSettings(prefs: prefs)
                .tabItem { Label(L("Generale"), systemImage: "gearshape") }
            MenuBarSettings(prefs: prefs, monitor: monitor)
                .tabItem { Label(L("Barra dei menu"), systemImage: "menubar.rectangle") }
            AlertsSettings(prefs: prefs, delivery: delivery)
                .tabItem { Label(L("Avvisi"), systemImage: "bell") }
        }
        .frame(width: 500)
        .id(prefs.language)   // cambio di lingua: ridisegna tutto subito
    }
}

// MARK: - Generale

private struct GeneralSettings: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

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
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.secondary)
                }
                Picker(L("Aggiorna ogni"), selection: $prefs.interval) {
                    Text(L("%d s", 1)).tag(1.0)
                    Text(L("%d s", 2)).tag(2.0)
                    Text(L("%d s", 5)).tag(5.0)
                }
                Picker(L("Lingua"), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text(L("A pannello aperto i dati si aggiornano ogni secondo."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("Modalità avanzata"), isOn: $prefs.advanced)
            } footer: {
                Text(L("Aggiunge la GPU, il carico di ogni core, tutti i sensori di temperatura e più app nei dettagli."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(L("Versione"), value: version)
                Link(L("Codice sorgente su GitHub"), destination: URL(string: "https://github.com/GGuidotz/whats-going-on")!)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Barra dei menu

private struct MenuBarSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        Form {
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
                Text(L("L'ordine dall'alto in basso è quello da sinistra a destra nella barra. Temperatura, GPU e consumo compaiono solo se questo Mac li fornisce."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker(L("Stile"), selection: $prefs.style) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(L("Anteprima")).foregroundStyle(.secondary)
                    Spacer()
                    MenuBarLabel(monitor: monitor, prefs: prefs)
                        .foregroundStyle(.primary)
                }
            }
        }
        .formStyle(.grouped)
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
                    Text(cocaineStatus).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(L("Invia un avviso di prova")) { delivery.sendTest(to: prefs.alertDestination) }
                    if let last = delivery.lastDelivered {
                        Text(last).font(.caption).foregroundStyle(.secondary)
                    }
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
                Text(L("Un avviso torna solo dopo che il valore è sceso sotto la soglia, e mai prima di questa attesa."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var cocaineStatus: String {
        if delivery.cocaineRunning { return L("Cocaine è aperto: gli avvisi arrivano nell'isola.") }
        if delivery.cocaineInstalled { return L("Cocaine è installato ma chiuso: finché non lo apri arrivano come notifiche.") }
        return L("Cocaine non è installato: gli avvisi arrivano come notifiche.")
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
