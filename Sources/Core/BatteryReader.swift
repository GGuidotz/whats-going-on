// Batteria: livello e stato da IOPowerSources (pubblico), cicli, salute, watt e temperatura da AppleSmartBattery.
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
        if let design = number("DesignCapacity")?.doubleValue, design > 0,
           let maxNow = (number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity"))?.doubleValue {
            sample.health = min(1.1, maxNow / design)
        }
        if let millivolts = number("Voltage")?.doubleValue,
           let milliamps = (number("InstantAmperage") ?? number("Amperage")).map({ Double(Int64(truncatingIfNeeded: $0.int64Value)) }) {
            sample.watts = millivolts * milliamps / 1_000_000
        }
        if let centi = number("Temperature")?.doubleValue, centi > 0 {
            sample.temperature = centi / 100
        }
    }
}
