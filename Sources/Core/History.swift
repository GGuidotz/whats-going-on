// Gli ultimi minuti di ogni misura, in memoria: servono ai grafici. Niente su disco.

import Foundation

struct Series: Equatable {
    let capacity: Int
    private(set) var values: [Double] = []

    init(capacity: Int) { self.capacity = capacity }

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    func suffix(_ n: Int) -> [Double] { Array(values.suffix(n)) }
}

enum Metric: String, CaseIterable, Codable, Identifiable {
    case cpu, memory, download, upload, temperature, gpu, power
    var id: String { rawValue }
}

struct History: Equatable {
    /// Quanto mostrano i grafici del pannello: 60 campioni (un minuto a pannello aperto).
    static let capacity = 60
    private(set) var series: [Metric: Series] = [:]

    subscript(metric: Metric) -> [Double] { series[metric]?.values ?? [] }

    func recent(_ metric: Metric, _ count: Int) -> [Double] { series[metric]?.suffix(count) ?? [] }

    mutating func record(_ s: Snapshot) {
        func add(_ metric: Metric, _ value: Double?) {
            guard let value else { return }
            series[metric, default: Series(capacity: Self.capacity)].append(value)
        }
        add(.cpu, s.cpu?.total)
        add(.memory, s.memory?.usedFraction)
        add(.download, s.network?.download)
        add(.upload, s.network?.upload)
        add(.temperature, s.sensors?.chip)
        add(.gpu, s.gpu?.utilization)
        add(.power, s.sensors?.systemWatts ?? s.battery?.watts.map(abs))
    }
}
