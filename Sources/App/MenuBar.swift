// Ciò che si vede nella barra dei menu: di predefinito CPU, memoria e velocità della rete, piccoli e fissi.
// Disegnato come immagine modello (template): macOS la colora per barra chiara, scura e selezionata
// (HIG, the-menu-bar.md › Menu bar extras). Ogni modulo ha una larghezza fissa e cifre tabellari, così la barra
// non si sposta quando i numeri cambiano.

import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var prefs: Preferences

    var body: some View {
        let modules = MenuBarContent.available(prefs.visibleModules, in: monitor.snapshot)
        if modules.isEmpty {
            Image(systemName: "waveform.path.ecg")
                .accessibilityLabel(Text("What's Going On"))
        } else {
            Image(nsImage: MenuBarContent.image(modules: modules, snapshot: monitor.snapshot,
                                                history: monitor.history, style: prefs.style))
                .renderingMode(.template)
                .accessibilityLabel(Text(MenuBarContent.spokenLabel(modules, monitor.snapshot)))
        }
    }
}

struct MenuBarContent: View {
    var modules: [MenuBarModule]
    var snapshot: Snapshot
    var history: History
    var style: MenuBarStyle

    /// Toglie i moduli senza dati su questo Mac (niente temperatura, niente consumo…).
    static func available(_ modules: [MenuBarModule], in s: Snapshot) -> [MenuBarModule] {
        modules.filter { m in
            switch m {
            case .temperature: s.sensors?.chip != nil
            case .gpu: s.gpu != nil
            case .power: s.sensors?.systemWatts != nil || s.battery?.watts != nil
            default: true
            }
        }
    }

    @MainActor
    static func image(modules: [MenuBarModule], snapshot: Snapshot, history: History, style: MenuBarStyle) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarContent(modules: modules, snapshot: snapshot, history: history, style: style))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }

    static func spokenLabel(_ modules: [MenuBarModule], _ s: Snapshot) -> String {
        modules.map { "\($0.title) \(value($0, s))" }.joined(separator: ", ")
    }

    static func value(_ m: MenuBarModule, _ s: Snapshot) -> String {
        switch m {
        case .cpu: s.cpu.map { Format.percent($0.total) } ?? "–"
        case .memory: s.memory.map { Format.percent($0.usedFraction) } ?? "–"
        case .network: s.network.map { "↓ " + Format.rate($0.download) + " ↑ " + Format.rate($0.upload) } ?? "–"
        case .temperature: s.sensors?.chip.map(Format.celsius) ?? "–"
        case .gpu: s.gpu.map { Format.percent($0.utilization) } ?? "–"
        case .disk: s.disk.map { Format.diskBytes($0.free) } ?? "–"
        case .power: (s.sensors?.systemWatts ?? s.battery?.watts).map(Format.watts) ?? "–"
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            ForEach(modules) { item($0) }
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 1)
        .frame(height: 22)
    }

    @ViewBuilder private func item(_ m: MenuBarModule) -> some View {
        switch m {
        case .network:
            HStack(spacing: 3) {
                if style == .graphs {
                    Sparkline(values: history.recent(.download, 30), upperBound: nil, slots: 30,
                              secondary: history.recent(.upload, 30), tint: .black)
                        .frame(width: 26, height: 14)
                }
                VStack(alignment: .trailing, spacing: -2) {
                    Text("↑ " + Format.compactRate(snapshot.network?.upload ?? 0))
                    Text("↓ " + Format.compactRate(snapshot.network?.download ?? 0))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .frame(width: 46, alignment: .trailing)
            }
        default:
            HStack(spacing: 3) {
                if style == .graphs, let metric = metric(m) {
                    Sparkline(values: history.recent(metric, 30), upperBound: upper(m), slots: 30, tint: .black)
                        .frame(width: 26, height: 14)
                } else {
                    Image(systemName: m.symbol).font(.system(size: 11, weight: .medium))
                }
                Text(short(m))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .frame(width: width(m), alignment: .trailing)
            }
        }
    }

    private func short(_ m: MenuBarModule) -> String {
        switch m {
        case .disk: snapshot.disk.map { Format.compactBytes($0.free) } ?? "–"
        case .power: (snapshot.sensors?.systemWatts ?? snapshot.battery?.watts).map { "\(Int(abs($0).rounded()))W" } ?? "–"
        default: Self.value(m, snapshot)
        }
    }

    private func width(_ m: MenuBarModule) -> CGFloat {
        switch m {
        case .temperature: 30
        case .disk: 40
        case .power: 30
        default: 34   // "100%"
        }
    }

    private func metric(_ m: MenuBarModule) -> Metric? {
        switch m {
        case .cpu: .cpu
        case .memory: .memory
        case .temperature: .temperature
        case .gpu: .gpu
        case .power: .power
        case .disk, .network: nil
        }
    }

    private func upper(_ m: MenuBarModule) -> Double? {
        switch m {
        case .cpu, .memory, .gpu: 1
        case .temperature: 110
        default: nil
        }
    }
}
