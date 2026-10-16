// Batteria: livello e stato da IOPowerSources (pubblico), cicli, salute, watt e temperatura da AppleSmartBattery;
// alimentatore e flusso di energia dagli stessi due posti, nessuna lettura in più.
// Un Mac da scrivania non ha batteria: read() restituisce nil e la riga non compare.

import Foundation
import IOKit
import IOKit.ps

final class BatteryReader {
    func read() -> BatterySample? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (desc["Type"] as? String) == "InternalBattery",
                  let current = desc["Current Capacity"] as? Int,
                  let max = desc["Max Capacity"] as? Int, max > 0 else { continue }

            let charging = desc["Is Charging"] as? Bool ?? false
            let onAC = (desc["Power Source State"] as? String) == "AC Power"
            let minutesKey = charging ? "Time to Full Charge" : "Time to Empty"
            let minutes = (desc[minutesKey] as? Int).flatMap { $0 > 0 ? $0 : nil }

            var sample = BatterySample(level: Double(current) / Double(max), isCharging: charging, onAC: onAC,
                                       minutesRemaining: minutes)
            addSmartBattery(to: &sample)
            return sample
        }
        return nil
    }

    private func addSmartBattery(to sample: inout BatterySample) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        func number(_ key: String) -> NSNumber? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
        }

        sample.cycles = number("CycleCount")?.intValue
        let design = number("DesignCapacity")?.intValue
        let maxNow = (number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity"))?.intValue
        if let design, design > 0, let maxNow {
            sample.health = min(1.1, Double(maxNow) / Double(design))
            sample.designCapacity = design
            sample.fullChargeCapacity = maxNow
        }
        if let millivolts = number("Voltage")?.doubleValue,
           let milliamps = (number("InstantAmperage") ?? number("Amperage")).map({ Double(Int64(truncatingIfNeeded: $0.int64Value)) }) {
            sample.watts = millivolts * milliamps / 1_000_000
        }
        if let centi = number("Temperature")?.doubleValue, centi > 0 {
            sample.temperature = centi / 100
        }

        // Il flusso di energia (Apple silicon): milliwatt che entrano dall'alimentatore e che consuma il Mac.
        if let telemetry = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] {
            if let input = (telemetry["SystemPowerIn"] as? NSNumber)?.doubleValue, input > 0, sample.onAC {
                sample.powerIn = input / 1000
            }
            if let load = (telemetry["SystemLoad"] as? NSNumber)?.doubleValue, load > 0 {
                sample.systemLoad = load / 1000
            }
        }
        if sample.onAC, let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            sample.adapterWatts = (adapter["Watts"] as? NSNumber)?.intValue
            let name = (adapter["Name"] as? String) ?? (adapter["Description"] as? String)
            sample.adapterName = name.flatMap { $0.isEmpty || $0 == "pd charger" ? nil : $0 }
        }
    }
}
