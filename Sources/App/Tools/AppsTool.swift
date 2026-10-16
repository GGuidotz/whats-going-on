// Attrezzi › App: chi pesa in memoria, chi fa lavorare la CPU, chi consuma energia, chi legge e scrive sul disco e chi
// usa la rete, adesso, con il gesto che serve davvero: chiudere l'app. "Chiudi" chiede all'app di chiudersi (salva o chiede di salvare); "Forza chiusura" solo con conferma.
// Si chiudono solo le app con l'icona nel Dock; per i processi di sistema c'è Monitoraggio Attività.
// Mentre questa scheda è aperta l'elenco si aggiorna a ogni lettura (SamplingNeeds.liveProcesses), poi torna ogni 10 s.

import AppKit
import SwiftUI

struct AppsView: View {
    enum Measure: String, CaseIterable, Identifiable {
        case memory, cpu, energy, disk, network
        var id: String { rawValue }
        var title: String {
            switch self {
            case .memory: L("Memoria")
            case .cpu: L("CPU")
            case .energy: L("Energia")
            case .disk: L("Disco")
            case .network: L("Rete")
            }
        }
    }

    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var mole: MoleRunner
    @ObservedObject var advice: AdviceModel
    @ObservedObject var prefs: Preferences
    @Binding var measure: Measure
    @State private var note: String?

    private var s: Snapshot { monitor.snapshot }

    private var apps: [ProcessUsage] {
        let list: [ProcessUsage]
        switch measure {
        case .memory: list = s.topByMemory
        case .cpu: list = s.topByCPU
        case .energy: list = s.topByEnergy
        case .disk: list = s.topByDisk
        case .network: list = s.topByNetwork
        }
        return Array(list.filter { $0.name != "kernel_task" }.prefix(10))
    }

    private var adviceText: String {
        switch measure {
        case .memory: AppAdvisor.memoryAdvice(s)
        case .cpu: AppAdvisor.cpuAdvice(s)
        case .energy: AppAdvisor.energyAdvice(s)
        case .disk: AppAdvisor.diskAdvice(s)
        case .network: AppAdvisor.networkAdvice(s, available: !s.topByNetwork.isEmpty)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                Text(adviceText)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentCard(padding: 12)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(apps) { AppRow(app: $0, measure: measure, top: apps.first, note: $note) }
                    }
                }
                if let note {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ToolSection(title: L("Manutenzione con Mole"), symbol: "wrench.and.screwdriver") {
                        MoleBox(runner: mole, command: .optimize)
                    }
                    if prefs.intelligence {
                        ToolSection(title: L("Apple Intelligence (sperimentale)"), symbol: "apple.intelligence") {
                            AdviceBox(advice: advice) { advice.ask(.apps, context: AppAdvisor.summary(s)) }
                        }
                    }
                }
                .padding(14)
            }
            .frame(width: 330)
        }
    }

    private var energyCaption: String {
        let total = s.topByEnergy.reduce(0) { $0 + ($1.energy ?? 0) }
        if let watts = s.sensors?.systemWatts ?? s.battery?.systemLoad {
            return L("Le app adesso: %@ · tutto il Mac: %@", Format.watts(total), Format.watts(watts))
        }
        return L("Le app adesso: %@", Format.watts(total))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                if let m = s.memory, measure == .memory {
                    Text(L("%@ di %@", Format.bytes(m.used), Format.bytes(m.total)))
                        .font(.title2.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
                    Text(L("Pressione %@ · swap %@", m.pressure.word, Format.bytes(m.swapUsed)))
                        .font(.callout).foregroundStyle(.secondary)
                } else if let c = s.cpu, measure == .cpu {
                    Text(L("CPU al %@", Format.percent(c.total)))
                        .font(.title2.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
                    Text(L("Utente %@ · Sistema %@", Format.percent(c.user), Format.percent(c.system)))
                        .font(.callout).foregroundStyle(.secondary)
                } else if measure == .energy {
                    Text(L("Energia delle app"))
                        .font(.title2.weight(.semibold)).fontDesign(.rounded)
                    Text(energyCaption).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                } else if measure == .disk {
                    let apps = s.topByDisk
                    Text(L("Disco: ↓ %@ · ↑ %@", Format.rate(apps.reduce(0) { $0 + ($1.diskRead ?? 0) }),
                           Format.rate(apps.reduce(0) { $0 + ($1.diskWrite ?? 0) })))
                        .font(.title2.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
                    Text(L("Letture e scritture delle app, adesso")).font(.callout).foregroundStyle(.secondary)
                } else if measure == .network, let n = s.network {
                    Text(L("Rete: ↓ %@ · ↑ %@", Format.rate(n.download), Format.rate(n.upload)))
                        .font(.title2.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
                    Text(L("Ricevuti e inviati da ogni app, adesso")).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker(L("Ordina per"), selection: $measure) {
                ForEach(Measure.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 340)
        }
        .padding(.top, 4)
    }
}

private struct AppRow: View {
    var app: ProcessUsage
    var measure: AppsView.Measure
    var top: ProcessUsage?
    @Binding var note: String?

    private var running: NSRunningApplication? { AppCloser.running(app) }

    /// Quanto è lunga la barra, rispetto alla prima dell'elenco.
    private var fraction: Double {
        switch measure {
        case .memory: Double(app.memory) / Double(max(1, top?.memory ?? 1))
        case .cpu: app.cpu / max(1, top?.cpu ?? 1)
        case .energy: (app.energy ?? 0) / max(0.01, top?.energy ?? 0)
        case .disk: app.disk / max(1, top?.disk ?? 0)
        case .network: app.net / max(1, top?.net ?? 0)
        }
    }

    /// Il valore della misura scelta, in grassetto.
    private var primary: String {
        switch measure {
        case .memory: Format.bytes(app.memory)
        case .cpu: Format.corePercent(app.cpu)
        case .energy: Format.watts(app.energy ?? 0)
        case .disk: "↓ " + Format.rate(app.diskRead ?? 0) + "  ↑ " + Format.rate(app.diskWrite ?? 0)
        case .network: "↓ " + Format.rate(app.netIn ?? 0) + "  ↑ " + Format.rate(app.netOut ?? 0)
        }
    }

    /// Accanto, in grigio: CPU se si guarda la memoria, memoria altrimenti.
    private var secondary: String {
        measure == .memory ? Format.corePercent(app.cpu) : Format.bytes(app.memory)
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let path = app.bundlePath {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
                } else {
                    Image(systemName: "gearshape.2").resizable().scaledToFit().foregroundStyle(.secondary).padding(3)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.name).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(primary)
                        .monospacedDigit().fontWeight(.semibold)
                    Text(secondary)
                        .monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 64, alignment: .trailing)
                }
                FillBar(fraction: min(1, fraction), tint: Palette.load(min(1, fraction) * 0.8))
                    .frame(height: 8)
            }
            if let running {
                Button(L("Chiudi")) {
                    note = AppCloser.quit(running, name: app.name, force: false)
                }
                .glassButton()
                .controlSize(.small)
                Menu {
                    Button(L("Forza chiusura…")) { note = AppCloser.quit(running, name: app.name, force: true) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(L("Altre azioni per %@", app.name))
            } else {
                Button(L("Monitoraggio Attività")) { AppCloser.openActivityMonitor() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(L("Processo di sistema o senza finestra: si gestisce da Monitoraggio Attività."))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

@MainActor
enum AppCloser {
    /// L'app in esecuzione con l'icona nel Dock che corrisponde a questa riga (nil per i processi senza app).
    static func running(_ app: ProcessUsage) -> NSRunningApplication? {
        guard let bundle = app.bundlePath else { return nil }
        let name = (bundle as NSString).lastPathComponent
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid()
                && ($0.bundleURL?.path == bundle || $0.bundleURL?.lastPathComponent == name)
        }
    }

    /// Chiude l'app e dice cosa è successo, in una frase.
    static func quit(_ app: NSRunningApplication, name: String, force: Bool) -> String {
        if force {
            guard ToolsAlert.confirm(title: L("Forzare la chiusura di %@?", name),
                                     message: L("Le modifiche non salvate andranno perse. Usala solo se l'app non risponde."),
                                     button: L("Forza chiusura")) else { return "" }
            diag(.app, "force quit \(name)")
            return app.forceTerminate() ? L("%@ chiusa.", name) : L("%@ non si è chiusa.", name)
        }
        diag(.app, "quit \(name)")
        return app.terminate()
            ? L("Ho chiesto a %@ di chiudersi: se ha documenti aperti, te lo chiede.", name)
            : L("%@ non ha risposto: prova Forza chiusura dal menu accanto.", name)
    }

    static func openActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
