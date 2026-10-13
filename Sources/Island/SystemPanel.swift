// La pagina "Sistema": la frase in alto, poi una riga per misura. È la stessa vista del pannello dell'app ed è
// pensata per diventare la pagina dell'isola di Cocaine: dipende solo da SystemMonitor (Sources/Core).

import SwiftUI

struct SummaryHeader: View {
    var summary: Summary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: summary.level.symbol)
                .font(.title2)
                .foregroundStyle(summary.level.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.title2.weight(.semibold))
                    .fontDesign(.rounded)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = summary.detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct SystemPanel: View {
    @ObservedObject var monitor: SystemMonitor
    var advanced: Bool

    @State private var expanded: Set<String> = []

    private var s: Snapshot { monitor.snapshot }
    private var h: History { monitor.history }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(key) },
                set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SummaryHeader(summary: monitor.summary)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 8) {
                cpuRow
                memoryRow
                networkRow
                if s.sensors?.chip != nil { temperatureRow }
                if advanced, s.gpu != nil { gpuRow }
                diskRow
                if s.battery != nil || s.sensors?.systemWatts != nil { energyRow }
            }
        }
    }

    // MARK: - Righe

    @ViewBuilder private var cpuRow: some View {
        let c = s.cpu
        MetricRow(symbol: "cpu", title: L("CPU"),
                  value: c.map { Format.percent($0.total) } ?? "–",
                  caption: c.map { L("Utente %@ · Sistema %@", Format.percent($0.user), Format.percent($0.system)) },
                  values: h.recent(.cpu, 60), upperBound: 1, tint: Palette.load(Severity.load(c?.total ?? 0)),
                  trend: trendText(h[.cpu]),
                  expanded: binding("cpu")) {
            if advanced, let c {
                DetailHeading(text: L("Core"))
                CoreBars(cores: c.perCore)
            }
            let top = Array(s.topByCPU.prefix(advanced ? 8 : 3))
            if !top.isEmpty {
                DetailHeading(text: L("App più attive"))
                ProcessList(processes: top, measure: .cpu)
            }
        }
    }

    @ViewBuilder private var memoryRow: some View {
        let m = s.memory
        MetricRow(symbol: "memorychip", title: L("Memoria"),
                  value: m.map { Format.percent($0.usedFraction) } ?? "–",
                  caption: m.map { L("%@ di %@", Format.bytes($0.used), Format.bytes($0.total)) },
                  values: h.recent(.memory, 60), upperBound: 1, tint: Palette.load(m.map { Severity.memory($0) } ?? 0),
                  trend: trendText(h[.memory]),
                  expanded: binding("memory")) {
            if let m {
                DetailLine(label: L("Pressione"), value: m.pressure.title)
                DetailLine(label: L("App"), value: Format.bytes(m.app))
                DetailLine(label: L("Riservata al sistema"), value: Format.bytes(m.wired))
                DetailLine(label: L("Compressa"), value: Format.bytes(m.compressed))
                if advanced { DetailLine(label: L("In cache"), value: Format.bytes(m.cached)) }
                DetailLine(label: L("Swap"), value: Format.bytes(m.swapUsed))
            }
            let top = Array(s.topByMemory.prefix(advanced ? 8 : 3))
            if !top.isEmpty {
                DetailHeading(text: L("App che usano più memoria"))
                ProcessList(processes: top, measure: .memory)
            }
        }
    }

    @ViewBuilder private var networkRow: some View {
        let n = s.network
        MetricRow(symbol: "arrow.up.arrow.down", title: L("Rete"),
                  value: n.map { "↓ " + Format.rate($0.download) } ?? "–",
                  caption: n.map { "↑ " + Format.rate($0.upload) },
                  values: h.recent(.download, 60), upperBound: nil, secondary: h.recent(.upload, 60),
                  tint: Palette.download, secondaryTint: Palette.upload,
                  trend: trendText(h[.download]),
                  expanded: binding("network")) {
            if let n {
                DetailLine(label: L("Download"), value: Format.rate(n.download))
                DetailLine(label: L("Upload"), value: Format.rate(n.upload))
                DetailLine(label: L("Ricevuti da quando è aperta"), value: Format.diskBytes(Int64(n.sessionIn)))
                DetailLine(label: L("Inviati da quando è aperta"), value: Format.diskBytes(Int64(n.sessionOut)))
                if let ip = n.localIP {
                    DetailLine(label: L("Indirizzo locale"), value: n.interface.map { "\(ip) (\($0))" } ?? ip)
                }
            }
        }
    }

    @ViewBuilder private var temperatureRow: some View {
        let t = s.sensors
        MetricRow(symbol: "thermometer.medium", title: L("Temperatura"),
                  value: t?.chip.map(Format.celsius) ?? "–",
                  caption: t?.gpu.map { L("GPU %@", Format.celsius($0)) },
                  values: h.recent(.temperature, 60), upperBound: 110,
                  tint: Palette.load(t?.chip.map(Severity.temperature) ?? 0),
                  trend: trendText(h[.temperature]),
                  expanded: binding("temperature")) {
            if let t {
                if let chip = t.chip { DetailLine(label: L("Chip, il punto più caldo"), value: Format.celsius(chip)) }
                if let gpu = t.gpu { DetailLine(label: L("GPU"), value: Format.celsius(gpu)) }
                if let b = s.battery?.temperature { DetailLine(label: L("Batteria"), value: Format.celsius(b)) }
                if advanced, !t.all.isEmpty {
                    DetailHeading(text: L("Tutti i sensori"))
                    ForEach(t.all) { DetailLine(label: $0.name, value: Format.celsius($0.celsius)) }
                }
            }
        }
    }

    @ViewBuilder private var gpuRow: some View {
        let g = s.gpu
        MetricRow(symbol: "square.stack.3d.up", title: L("GPU"),
                  value: g.map { Format.percent($0.utilization) } ?? "–",
                  caption: g?.memoryUsed.map { L("%@ di memoria", Format.bytes($0)) },
                  values: h.recent(.gpu, 60), upperBound: 1, tint: Palette.load(Severity.load(g?.utilization ?? 0)),
                  trend: trendText(h[.gpu]),
                  expanded: binding("gpu")) {
            if let g {
                DetailLine(label: L("Utilizzo"), value: Format.percent(g.utilization))
                if let mem = g.memoryUsed { DetailLine(label: L("Memoria in uso"), value: Format.bytes(mem)) }
            }
        }
    }

    @ViewBuilder private var diskRow: some View {
        let d = s.disk
        MetricRow(symbol: "internaldrive", title: L("Disco"),
                  value: d.map { L("%@ liberi", Format.diskBytes($0.free)) } ?? "–",
                  caption: d.map { L("di %@", Format.diskBytes($0.total)) },
                  values: h.recent(.diskRead, 60), upperBound: nil, secondary: h.recent(.diskWrite, 60),
                  tint: Palette.load(d.map { Severity.remaining($0.freeFraction) } ?? 0),
                  trend: nil,
                  expanded: binding("disk")) {
            if let d {
                DetailLine(label: L("Lettura"), value: Format.rate(d.readRate))
                DetailLine(label: L("Scrittura"), value: Format.rate(d.writeRate))
                DetailLine(label: L("Libero"), value: Format.percent(d.freeFraction))
            }
        }
    }

    @ViewBuilder private var energyRow: some View {
        let b = s.battery
        let watts = s.sensors?.systemWatts
        MetricRow(symbol: b.map(batterySymbol) ?? "bolt",
                  title: b != nil ? L("Batteria") : L("Consumo"),
                  value: b.map { Format.percent($0.level) } ?? watts.map(Format.watts) ?? "–",
                  caption: b.map(batteryCaption) ?? nil,
                  values: h.recent(.power, 60), upperBound: nil,
                  tint: Palette.load(b.map { Severity.remaining($0.level) } ?? watts.map(Severity.watts) ?? 0),
                  trend: nil,
                  expanded: binding("energy")) {
            if let watts { DetailLine(label: L("Consumo del Mac"), value: Format.watts(watts)) }
            if let b {
                if let w = b.watts {
                    DetailLine(label: w >= 0 ? L("Potenza in carica") : L("Potenza dalla batteria"), value: Format.watts(w))
                }
                if let health = b.health { DetailLine(label: L("Salute"), value: Format.percent(health)) }
                if let cycles = b.cycles { DetailLine(label: L("Cicli"), value: "\(cycles)") }
                if let t = b.temperature { DetailLine(label: L("Temperatura"), value: Format.celsius(t)) }
            }
        }
    }

    private func batterySymbol(_ b: BatterySample) -> String {
        if b.isCharging { return "battery.100percent.bolt" }
        switch b.level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func batteryCaption(_ b: BatterySample) -> String? {
        let state = b.isCharging ? L("In carica") : (b.onAC ? L("Collegato all'alimentazione") : L("A batteria"))
        guard let minutes = b.minutesRemaining else { return state }
        return b.isCharging
            ? L("%@ · piena tra %@", state, Format.minutes(minutes))
            : L("%@ · ancora %@", state, Format.minutes(minutes))
    }
}
