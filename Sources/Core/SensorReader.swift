// Temperature e consumo.
// - Apple silicon: i sensori di temperatura passano dal sistema eventi HID. Le funzioni per leggerli esistono in IOKit
//   ma non sono documentate: le dichiariamo qui sotto, isolate in questo file. Se un aggiornamento di macOS le cambia,
//   la riga Temperatura sparisce invece di rompere l'app.
// - Intel: temperatura della CPU dall'SMC (TC0P e simili).
// - Consumo totale del Mac: chiave SMC PSTR, dove c'è.

import Foundation
import IOKit

// MARK: - Funzioni HID non documentate (stessa firma usata da Stats e da altri monitor open source)

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> CFTypeRef?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: CFTypeRef, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: CFTypeRef) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: CFTypeRef, _ key: CFString) -> CFTypeRef?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> CFTypeRef?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

final class SensorReader {
    private static let temperatureEvent: Int64 = 15            // kIOHIDEventTypeTemperature
    private static let temperatureField: Int32 = 15 << 16      // IOHIDEventFieldBase(kIOHIDEventTypeTemperature)

    private let smc = SMC()
    private var client: CFTypeRef?
    private var services: [(name: String, service: CFTypeRef)] = []
    private let isAppleSilicon: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }()

    init() {
        guard isAppleSilicon, let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return }
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, matching)
        self.client = client
        if let list = IOHIDEventSystemClientCopyServices(client) as? [CFTypeRef] {
            services = list.compactMap { service -> (name: String, service: CFTypeRef)? in
                guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String else { return nil }
                return (name, service)
            }
        }
    }

    func read() -> SensorsSample? {
        var sensors: [TemperatureSensor] = []
        var chip: Double?
        var gpu: Double?

        if isAppleSilicon {
            // Più sensori con lo stesso nome: teniamo il più caldo.
            var byName: [String: Double] = [:]
            for (name, service) in services {
                guard let event = IOHIDServiceClientCopyEvent(service, Self.temperatureEvent, 0, 0) else { continue }
                let value = IOHIDEventGetFloatValue(event, Self.temperatureField)
                guard value > 0, value < 130 else { continue }
                byName[name] = max(byName[name] ?? 0, value)
            }
            sensors = byName.map { TemperatureSensor(name: $0.key, celsius: $0.value) }.sorted { $0.name < $1.name }
            let die = sensors.filter { Self.isChipSensor($0.name) }.map(\.celsius)
            chip = die.max()
            gpu = sensors.filter { $0.name.localizedCaseInsensitiveContains("GPU") }.map(\.celsius).max()
        } else if let smc {
            for key in ["TC0P", "TC0D", "TC0E", "TC0F", "TCXC"] {
                if let value = smc.value(key), value > 0, value < 130 {
                    sensors.append(TemperatureSensor(name: key, celsius: value))
                }
            }
            chip = sensors.map(\.celsius).max()
            if let value = smc.value("TG0P"), value > 0, value < 130 {
                gpu = value
                sensors.append(TemperatureSensor(name: "TG0P", celsius: value))
            }
        }

        var watts: Double?
        if let value = smc?.value("PSTR"), value > 0.1, value < 1000 { watts = value }

        guard chip != nil || watts != nil || !sensors.isEmpty else { return nil }
        return SensorsSample(chip: chip, gpu: gpu, systemWatts: watts, all: sensors)
    }

    /// I sensori del die: "PMU tdie…", "pACC/eACC MTR Temp Sensor…", "SOC MTR…". Non NAND, batteria o gas gauge.
    private static func isChipSensor(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("tdie") || n.contains("acc mtr") || n.contains("soc mtr") || n.contains("cpu")
    }
}
