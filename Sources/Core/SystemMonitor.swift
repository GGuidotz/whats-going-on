// Il campionatore: un solo timer su una coda in background legge tutto, poi pubblica l'istantanea sul thread
// principale. Niente SwiftUI qui: lo stesso motore può servire la pagina dell'isola di Cocaine.
//
// Leggerezza (obiettivo: sotto l'1% di CPU). Si legge solo ciò che qualcuno guarda:
// - pannello aperto: tutto, ogni secondo;
// - pannello chiuso: CPU, memoria e rete al passo scelto (2 s di predefinito); app ogni 10 s (servono alla frase e
//   all'avviso "app che consuma"); temperature solo dei sensori del chip e solo se servono (nella barra o con l'avviso
//   "chip caldo" acceso), ogni 30 s di predefinito; batteria ogni 10 s; spazio su disco ogni minuto;
// - attrezzo App aperto: le app a ogni lettura, con disco, energia e rete (nettop, al massimo ogni 3 s);
// - schermi spenti o Mac bloccato: una lettura ogni 10 s, e gli avvisi continuano (sei via: è lì che servono);
// - tutti i processi, anche di sistema (ps, BackgroundActivity.swift): ogni 30 s a pannello chiuso, 10 s aperto, per
//   dire chi lavora da molto e se Spotlight indicizza;
// - stato termico e da quanto è acceso: a ogni lettura, costano una chiamata ciascuno.
// La cronologia lunga (LongHistory.swift) prende un punto al minuto dalle stesse letture: nessuna lettura in più.
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
    /// L'attrezzo "App" è aperto: l'elenco delle app a ogni lettura, non ogni 10 s.
    var liveProcesses = false
    /// Tutti i processi, anche di sistema (ps): per "da quanto lavora" e Spotlight.
    var systemProcesses = true
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
    private let appNetwork = AppNetworkReader()
    private var wasLive = false
    private let gpu = GPUReader()
    private lazy var sensors = SensorReader()
    private var activity = BackgroundActivityTracker()

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
        if needs.liveProcesses {
            // L'attrezzo App: anche disco, energia e rete di ogni app.
            s.processes = processes.read(detailed: true, network: appNetwork.latest())
        } else {
            if wasLive { appNetwork.reset() }
            s.processes = (panel || due("processes", every: 10, now: now)) ? processes.read() : last.processes
        }
        wasLive = needs.liveProcesses
        if panel { s.load = LoadReader.read() }
        if needs.systemProcesses {
            if due("system", every: panel ? 10 : 30, now: now) {
                if let list = SystemProcessReader.read() {
                    (s.runaways, s.spotlight) = activity.update(list, now: s.date)
                }
            } else {
                s.runaways = last.runaways
                s.spotlight = last.spotlight
            }
        }
        s.thermal = ThermalLevel.current
        s.uptime = BootTime.uptime(at: s.date)
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
    /// Un punto al minuto per 7 giorni. Cambia una volta al minuto, non a ogni lettura.
    @Published private(set) var longHistory = LongHistory()
    /// Salvare la cronologia sul Mac (Impostazioni › Generale). Spenta: niente file e niente punti nuovi.
    var keepsHistory = true {
        didSet {
            guard keepsHistory != oldValue else { return }
            if keepsHistory { store = LongHistory.load(); longHistory = store } else { clearHistory() }
        }
    }
    /// Elementi di avvio orfani, dall'app (StartupScanner): entrano nella frase.
    var startupOrphans: Int?

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
    private let saveQueue = DispatchQueue(label: "local.whatsgoingon.history", qos: .background)
    private var lastSave = Date()
    /// La cronologia che si aggiorna a ogni lettura; `longHistory` ne è la copia pubblicata, una volta al minuto.
    private var store = LongHistory()
    private var derivedMinute: Int32 = 0
    private var swapTrend: SwapTrend?
    private var diskForecast: DiskForecast?

    init() {
        store = LongHistory.load()
        longHistory = store
        schedule()
    }

    /// Scrive la cronologia sul disco (in background). All'uscita e ogni 10 minuti.
    func saveHistory(wait: Bool = false) {
        guard keepsHistory else { return }
        lastSave = Date()
        let data = store.encoded()
        let work: @Sendable () -> Void = {
            do { try LongHistory.save(data) } catch { NSLog("What's Going On: history not saved: \(error)") }
        }
        if wait { saveQueue.sync(execute: work) } else { saveQueue.async(execute: work) }
    }

    /// Cancella la cronologia: in memoria e sul disco.
    func clearHistory() {
        store.clear()
        longHistory = store
        derivedMinute = 0
        saveQueue.async { LongHistory.delete() }
    }

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

    private func apply(_ sample: Snapshot) {
        var s = sample
        if keepsHistory, store.record(s) {
            // Si ripubblica solo quando si chiude un minuto: SwiftUI ridisegna i grafici lunghi di rado.
            longHistory = store
            if s.date.timeIntervalSince(lastSave) >= 600 { saveHistory() }
        }
        // Tendenza dello swap e previsione del disco: si ricalcolano una volta al minuto.
        let minute = HistoryPoint.minute(of: s.date)
        if minute != derivedMinute {
            derivedMinute = minute
            swapTrend = s.memory.map { store.swapTrend(current: $0.swapUsed, now: s.date) }
            diskForecast = s.disk.flatMap { store.diskForecast(free: $0.free, now: s.date) }
        }
        s.swapTrend = swapTrend
        s.diskForecast = diskForecast
        s.startupOrphans = startupOrphans
        snapshot = s
        history.record(s)
        let next = summaryEngine.update(s)
        if next != summary { summary = next }
        for event in alertEngine.evaluate(s, settings: alertSettings) { onAlert?(event) }
    }
}
