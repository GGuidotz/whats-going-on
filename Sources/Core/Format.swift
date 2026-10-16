// Numeri leggibili, nella lingua dell'app.

import Foundation

enum Format {
    /// 0.234 → "23%"
    static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, fraction) * 100).rounded()))%"
    }

    /// Percento di core come Monitoraggio Attività: 1.8 core → "180%".
    static func corePercent(_ value: Double) -> String {
        "\(Int(max(0, value).rounded()))%"
    }

    /// Memoria e dischi: "12,4 GB".
    static func bytes<T: BinaryInteger>(_ value: T) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useMB, .useGB, .useTB]
        return f.string(fromByteCount: Int64(value))
    }

    /// Spazio su disco, in base 1000 come il Finder.
    static func diskBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// Velocità: "820 KB/s", "1,2 MB/s". Base 1000, come le velocità di rete.
    static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["KB/s", "MB/s", "GB/s"]
        var value = max(0, bytesPerSecond) / 1000
        var i = 0
        while value >= 999.5 && i < units.count - 1 {
            value /= 1000
            i += 1
        }
        let digits = (i > 0 && value < 9.95) ? 1 : 0
        return number(value, digits: digits) + " " + units[i]
    }

    /// Velocità compatta per la barra dei menu: "1,2M", "820K".
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let units = ["K", "M", "G"]
        var value = max(0, bytesPerSecond) / 1000
        var i = 0
        while value >= 999.5 && i < units.count - 1 {
            value /= 1000
            i += 1
        }
        let digits = (i > 0 && value < 9.95) ? 1 : 0
        return number(value, digits: digits) + units[i]
    }

    /// Spazio compatto per la barra dei menu: "120G", "1,2T".
    static func compactBytes(_ value: Int64) -> String {
        let units = ["M", "G", "T"]
        var v = Double(max(0, value)) / 1_000_000
        var i = 0
        while v >= 999.5 && i < units.count - 1 {
            v /= 1000
            i += 1
        }
        return number(v, digits: (i > 1 && v < 9.95) ? 1 : 0) + units[i]
    }

    static func celsius(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    static func watts(_ value: Double) -> String {
        number(abs(value), digits: abs(value) < 10 ? 1 : 0) + " W"
    }

    static func number(_ value: Double, digits: Int) -> String {
        let f = NumberFormatter()
        f.locale = Localization.locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.\(digits)f", value)
    }

    /// "2 h 05 min", "45 min".
    static func minutes(_ total: Int) -> String {
        let h = total / 60, m = total % 60
        return h > 0 ? L("%d h %02d min", h, m) : L("%d min", m)
    }

    /// Da quanto è acceso: "3 giorni, 4 h", "5 h 20 min".
    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds / 60)
        let days = total / 1440
        if days > 0 { return days == 1 ? L("1 giorno, %d h", total % 1440 / 60) : L("%d giorni, %d h", days, total % 1440 / 60) }
        return minutes(total)
    }
}
