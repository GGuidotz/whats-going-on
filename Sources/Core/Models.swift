// I dati di un istante. Tutto è opzionale: un Mac senza batteria, o un sensore che non risponde, lascia il campo nil
// e l'interfaccia nasconde la riga invece di mostrare zeri finti.

import Foundation

struct CPUSample: Equatable {
    /// 0…1, media di tutti i core.
    var total: Double
    var user: Double
    var system: Double
    /// 0…1 per core, nell'ordine del kernel.
    var perCore: [Double]
}

enum MemoryPressure: Int, Equatable {
    case normal = 1, warning = 2, critical = 4
}

struct MemorySample: Equatable {
    var total: UInt64
    /// Come "Memoria usata" di Monitoraggio Attività: app + wired + compressa.
    var used: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var cached: UInt64
    var swapUsed: UInt64
    var pressure: MemoryPressure

    var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

struct NetworkSample: Equatable {
    /// Byte al secondo.
    var download: Double
    var upload: Double
    /// Byte dall'avvio dell'app.
    var sessionIn: UInt64
    var sessionOut: UInt64
    var localIP: String?
    var interface: String?
}

struct DiskSample: Equatable {
    var total: Int64
    var free: Int64

    var freeFraction: Double { total > 0 ? Double(free) / Double(total) : 1 }
}

struct BatterySample: Equatable {
    /// 0…1
    var level: Double
    var isCharging: Bool
    var onAC: Bool
    /// Minuti alla fine o alla carica completa; nil se macOS li sta ancora calcolando.
    var minutesRemaining: Int?
    var cycles: Int?
    /// Capacità attuale rispetto a quella di fabbrica, 0…1.
    var health: Double?
    /// Watt: positivo in carica, negativo in scarica.
    var watts: Double?
    var temperature: Double?
}

struct TemperatureSensor: Equatable, Identifiable {
    var name: String
    var celsius: Double
    var id: String { name }
}

struct SensorsSample: Equatable {
    /// La temperatura più alta del chip (CPU/SoC), in gradi.
    var chip: Double?
    var gpu: Double?
    /// Consumo dell'intero Mac in watt (SMC), se il Mac lo espone.
    var systemWatts: Double?
    var all: [TemperatureSensor]
}

struct GPUSample: Equatable {
    /// 0…1
    var utilization: Double
    var memoryUsed: UInt64?
}

/// Un'app o un processo, con gli aiutanti sommati (Safari conta anche i suoi processi web).
struct ProcessUsage: Equatable, Identifiable {
    var name: String
    /// Percento di un core: 100 = un core pieno, come Monitoraggio Attività.
    var cpu: Double
    var memory: UInt64
    var id: String { name }
}

struct Snapshot: Equatable {
    var date = Date()
    var cpu: CPUSample?
    var memory: MemorySample?
    var network: NetworkSample?
    var disk: DiskSample?
    var battery: BatterySample?
    var sensors: SensorsSample?
    var gpu: GPUSample?
    /// Le app più attive per CPU e per memoria (al massimo 12 + 12, senza doppioni).
    var processes: [ProcessUsage] = []
    /// What's Going On stessa: quanto pesa adesso.
    var ownUsage: ProcessUsage?

    var topByCPU: [ProcessUsage] { processes.sorted { $0.cpu > $1.cpu } }
    var topByMemory: [ProcessUsage] { processes.sorted { $0.memory > $1.memory } }
}
