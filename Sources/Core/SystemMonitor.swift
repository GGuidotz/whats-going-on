// Il campionatore: un solo timer su una coda in background legge tutto, poi pubblica l'istantanea sul thread
// principale. Niente SwiftUI qui: lo stesso motore può servire la pagina dell'isola di Cocaine.
//
// Leggerezza (obiettivo: sotto l'1% di CPU). Si legge solo ciò che qualcuno guarda:
// - pannello aperto: tutto, ogni secondo;
// - pannello chiuso: CPU, memoria e rete al passo scelto (2 s di predefinito); app ogni 10 s (servono alla frase e
//   all'avviso "app che consuma"); temperature solo dei sensori del chip e solo se servono (nella barra o con l'avviso
//   "chip caldo" acceso), ogni 30 s di predefinito; batteria ogni 10 s; spazio su disco ogni minuto;
// - schermi spenti o Mac bloccato: una lettura ogni 10 s, e gli avvisi continuano (sei via: è lì che servono).
// Il timer ha una tolleranza ampia, così macOS può accorpare i risvegli con quelli delle altre app.

import Combine
import Foundation

/// Cosa serve leggere, deciso da chi usa il motore (barra, avvisi, pannello).
struct SamplingNeeds: Equatable {
    /// Il pannello è aperto: si legge tutto, ogni secondo.
    var panelOpen = false
    var gpu = false
    /// Temperatura del chip a pannello chiuso: nella barra o per l'avviso "chip caldo".
    var temperature = true
    /// Ogni quanti secondi leggerla a pannello chiuso.
    var temperatureInterval: Double = 30
    /// Consumo in watt a pannello chiuso: nella barra.
    var power = false
    /// Modalità avanzata: a pannello aperto anche l'elenco di tutti i sensori.
    var allSensors = false
}

/// Tutti i lettori. Usato solo dalla coda del campionatore.
final class Sampler: @unchecked Sendable {
    private let cpu = CPUReader()
    private let memory = MemoryReader()
    private let network = NetworkReader()
    private let disk = DiskReader()
    private let battery = BatteryReader()
    private let processes = ProcessReader()
    private let own = OwnUsageReader()
    private let gpu = GPUReader()
    private lazy var sensors = SensorReader()

    private var last = Snapshot()
    /// Quando è stata fatta l'ultima lettura di ciascun gruppo (secondi di uptime).
    private var lastRead: [String: Double] = [:]

    private func due(_ key: String, every seconds: Double, now: Double) -> Bool {
        guard let previous = lastRead[key], now - previous < seconds - 0.25 else {
            lastRead[key] = now
            return true
        }
        return false
    }

    func sample(_ needs: SamplingNeeds) -> Snapshot {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        let panel = needs.panelOpen
        var s = Snapshot(date: Date())
        s.cpu = cpu.read()
        s.memory = memory.read()
        s.network = network.read(withAddress: panel)

        s.disk = due("disk", every: 60, now: now) ? disk.read() : last.disk
        s.battery = due("battery", every: panel ? 5 : 10, now: now) ? battery.read() : last.battery

        var sensorsSample = last.sensors
        if panel || needs.temperature {
            if due("sensors", every: panel ? 1 : needs.temperatureInterval, now: now) {
                sensorsSample = sensors.read(all: panel && needs.allSensors)
            }
        } else {
            sensorsSample = nil
        }
        let watts = (panel || needs.power) ? sensors.watts() : nil
        if sensorsSample != nil || watts != nil {
            var merged = sensorsSample ?? SensorsSample(chip: nil, gpu: nil, systemWatts: nil, all: [])
            merged.systemWatts = watts
            s.sensors = merged
        }

        if needs.gpu { s.gpu = gpu.read() }
        s.processes = (panel || due("processes", every: 10, now: now)) ? processes.read() : last.processes
        s.ownUsage = own.read()
        last = s
        return s
    }
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var history = History()
    @Published private(set) var summary = Summary.starting

    /// Secondi tra due letture a pannello chiuso.
    var interval: Double = 2 { didSet { if interval != oldValue { schedule() } } }
    var isPanelOpen: Bool {
        get { needs.panelOpen }
        set { needs.panelOpen = newValue }
    }
    /// Schermi spenti o Mac bloccato: letture lente.
    var isAway = false { didSet { if isAway != oldValue { schedule() } } }
    var needs = SamplingNeeds() { didSet { if needs != oldValue { schedule() } } }
    var alertSettings = AlertSettings()
    /// Chiamato sul thread principale per ogni avviso che scatta.
    var onAlert: ((AlertEvent) -> Void)?

    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "local.whatsgoingon.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var summaryEngine = SummaryEngine()
    private var alertEngine = AlertEngine()

    init() { schedule() }

    private func schedule() {
        timer?.cancel()
        let period = needs.panelOpen ? 1.0 : (isAway ? max(10, interval) : max(1, interval))
        let t = DispatchSource.makeTimerSource(queue: queue)
        // a pannello aperto il ritmo deve essere regolare; chiuso, macOS può spostare la lettura di un quarto
        let leeway = needs.panelOpen ? 0.1 : 0.25
        t.schedule(deadline: .now(), repeating: period, leeway: .milliseconds(Int(period * leeway * 1000)))
        let sampler = sampler
        let needs = needs
        // Il monitor vive quanto l'app: il riferimento forte non perde nulla.
        t.setEventHandler {
            let s = sampler.sample(needs)
            Task { @MainActor in self.apply(s) }
        }
        t.resume()
        timer = t
    }

    private func apply(_ s: Snapshot) {
        snapshot = s
        history.record(s)
        let next = summaryEngine.update(s)
        if next != summary { summary = next }
        for event in alertEngine.evaluate(s, settings: alertSettings) { onAlert?(event) }
    }
}
