// Il campionatore: un solo timer su una coda in background legge tutto, poi pubblica l'istantanea sul thread
// principale. Più veloce a pannello aperto (1 s), al passo scelto a pannello chiuso (2 s di predefinito).
// Leggerezza (obiettivo: sotto l'1% di CPU): a pannello chiuso l'elenco delle app, la lettura più cara, si fa una volta
// su tre e i sensori una su due; la barra si ridisegna solo se l'immagine cambia (StatusItem).
// Niente SwiftUI qui: lo stesso motore può servire la pagina dell'isola di Cocaine.

import Combine
import Foundation

/// Tutti i lettori. Usato solo dalla coda del campionatore.
final class Sampler: @unchecked Sendable {
    private let cpu = CPUReader()
    private let memory = MemoryReader()
    private let network = NetworkReader()
    private let disk = DiskReader()
    private let battery = BatteryReader()
    private let processes = ProcessReader()
    private let gpu = GPUReader()
    private lazy var sensors = SensorReader()
    private var tick = 0
    private var lastBattery: BatterySample?
    private var lastSensors: SensorsSample?
    private var lastProcesses: [ProcessUsage] = []

    /// `detailed`: il pannello è aperto e mostra le app, quindi l'elenco va letto a ogni giro.
    func sample(includeGPU: Bool, detailed: Bool) -> Snapshot {
        tick += 1
        var s = Snapshot(date: Date())
        s.cpu = cpu.read()
        s.memory = memory.read()
        s.network = network.read()
        s.disk = disk.read(refreshCapacity: tick % 30 == 1)
        if tick % 5 == 1 { lastBattery = battery.read() }      // la batteria cambia piano
        s.battery = lastBattery
        if tick % 2 == 1 { lastSensors = sensors.read() }      // i sensori costano un po' di più
        s.sensors = lastSensors
        if includeGPU { s.gpu = gpu.read() }
        // a pannello chiuso le app servono solo alla frase di riepilogo: basta una lettura ogni tre
        if detailed || tick % 3 == 1 { lastProcesses = processes.read() }
        s.processes = lastProcesses
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
    var isPanelOpen = false { didSet { if isPanelOpen != oldValue { schedule() } } }
    var includeGPU = false
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
        let period = isPanelOpen ? 1.0 : max(1, interval)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: period, leeway: .milliseconds(Int(period * 100)))
        let sampler = sampler
        let gpu = includeGPU
        let detailed = isPanelOpen
        // Il monitor vive quanto l'app: il riferimento forte non perde nulla.
        t.setEventHandler {
            let s = sampler.sample(includeGPU: gpu, detailed: detailed)
            Task { @MainActor in self.apply(s) }
        }
        t.resume()
        timer = t
    }

    /// Da chiamare quando cambia la modalità avanzata, così la GPU entra o esce dalle letture.
    func refreshConfiguration() { schedule() }

    private func apply(_ s: Snapshot) {
        snapshot = s
        history.record(s)
        let next = summaryEngine.update(s)
        if next != summary { summary = next }
        for event in alertEngine.evaluate(s, settings: alertSettings) { onAlert?(event) }
    }
}
