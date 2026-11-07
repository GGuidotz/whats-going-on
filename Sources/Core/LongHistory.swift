// La cronologia lunga: un punto al minuto per 7 giorni, salvata sul Mac. Serve a dire da quando (lo swap che cresce,
// il disco che si riempie) e a disegnare le 24 ore e i 7 giorni. Solo numeri aggregati: niente nomi di app o di file.
// Il file sta in ~/Library/Application Support/What's Going On/history.bin, circa 360 KB pieno (36 byte a punto);
// si riscrive al massimo ogni 10 minuti e all'uscita. Le Impostazioni lo spengono o lo cancellano.

import Foundation

/// Un minuto. I valori mancanti (niente sensori, disco non ancora letto) sono NaN.
struct HistoryPoint: Equatable {
    /// Minuti dal 1° gennaio 2001 (la data di riferimento di Foundation).
    var minute: Int32
    /// CPU: media e picco del minuto, 0…1.
    var cpu: Float
    var cpuPeak: Float
    /// Memoria usata, frazione media.
    var memory: Float
    /// Byte: compressa (media), swap (ultimo valore), spazio libero sul disco (ultimo valore).
    var compressed: Float
    var swap: Float
    var diskFree: Float
    /// Pressione della memoria, la peggiore del minuto (1, 2, 4).
    var pressure: Float
    /// Temperatura del chip, la più alta del minuto.
    var temperature: Float

    var date: Date { Date(timeIntervalSinceReferenceDate: Double(minute) * 60) }

    static func minute(of date: Date) -> Int32 { Int32(floor(date.timeIntervalSinceReferenceDate / 60)) }
}

/// Lo swap negli ultimi minuti: quanto è cambiato.
struct SwapTrend: Equatable {
    var current: UInt64
    /// Byte in più (o in meno) rispetto a 30 e 60 minuti fa; nil se la cronologia non arriva fin lì.
    var change30: Int64?
    var change60: Int64?
}

/// Quando si riempirà il disco, al ritmo degli ultimi giorni.
struct DiskForecast: Equatable {
    /// Byte persi al giorno.
    var bytesPerDay: Double
    var daysLeft: Double
}

struct LongHistory: Equatable {
    static let retention = 7 * 1440
    private static let magic: UInt32 = 0x57474F48   // "WGOH"
    private static let formatVersion: UInt32 = 1
    private static let fields = 8

    private(set) var points: [HistoryPoint] = []

    private struct Bucket: Equatable {
        var minute: Int32
        var count = 0
        var cpuSum = 0.0, cpuCount = 0, cpuPeak = 0.0
        var memorySum = 0.0, memoryCount = 0
        var compressedSum = 0.0
        var swap = Double.nan, diskFree = Double.nan
        var pressure = 0.0
        var temperature = Double.nan
    }

    private var bucket: Bucket?

    // MARK: Registrazione

    /// Aggiunge un'istantanea al minuto in corso. true quando un minuto si è chiuso ed è diventato un punto.
    @discardableResult
    mutating func record(_ s: Snapshot) -> Bool {
        let minute = HistoryPoint.minute(of: s.date)
        var closed = false
        if let b = bucket, b.minute != minute {
            append(point(from: b))
            bucket = nil
            closed = true
        }
        var b = bucket ?? Bucket(minute: minute)
        b.count += 1
        if let c = s.cpu { b.cpuSum += c.total; b.cpuCount += 1; b.cpuPeak = max(b.cpuPeak, c.total) }
        if let m = s.memory {
            b.memorySum += m.usedFraction
            b.compressedSum += Double(m.compressed)
            b.memoryCount += 1
            b.swap = Double(m.swapUsed)
            b.pressure = max(b.pressure, Double(m.pressure.rawValue))
        }
        if let d = s.disk { b.diskFree = Double(d.free) }
        if let t = s.sensors?.chip { b.temperature = b.temperature.isNaN ? t : max(b.temperature, t) }
        bucket = b
        return closed
    }

    private func point(from b: Bucket) -> HistoryPoint {
        HistoryPoint(minute: b.minute,
                     cpu: b.cpuCount > 0 ? Float(b.cpuSum / Double(b.cpuCount)) : .nan,
                     cpuPeak: b.cpuCount > 0 ? Float(b.cpuPeak) : .nan,
                     memory: b.memoryCount > 0 ? Float(b.memorySum / Double(b.memoryCount)) : .nan,
                     compressed: b.memoryCount > 0 ? Float(b.compressedSum / Double(b.memoryCount)) : .nan,
                     swap: Float(b.swap), diskFree: Float(b.diskFree),
                     pressure: b.pressure > 0 ? Float(b.pressure) : .nan,
                     temperature: Float(b.temperature))
    }

    private mutating func append(_ p: HistoryPoint) {
        if let last = points.last, last.minute >= p.minute { return }   // orologio tornato indietro: si salta
        points.append(p)
        let oldest = p.minute - Int32(Self.retention)
        if let first = points.first, first.minute <= oldest {
            points.removeAll { $0.minute <= oldest }
        }
    }

    mutating func clear() {
        points = []
        bucket = nil
    }

    // MARK: Domande

    /// I punti degli ultimi `minutes` minuti.
    func recent(minutes: Int, now: Date) -> ArraySlice<HistoryPoint> {
        let from = HistoryPoint.minute(of: now) - Int32(minutes)
        let start = points.firstIndex { $0.minute > from } ?? points.endIndex
        return points[start...]
    }

    /// Il punto più vicino a `minutesAgo` minuti fa, con al massimo 5 minuti di scarto.
    private func point(minutesAgo: Int, now: Date) -> HistoryPoint? {
        let target = HistoryPoint.minute(of: now) - Int32(minutesAgo)
        return recent(minutes: minutesAgo + 6, now: now)
            .filter { abs($0.minute - target) <= 5 && !$0.swap.isNaN }
            .min { abs($0.minute - target) < abs($1.minute - target) }
    }

    func swapTrend(current: UInt64, now: Date) -> SwapTrend {
        func change(_ minutes: Int) -> Int64? {
            point(minutesAgo: minutes, now: now).map { Int64(current) - Int64(Double($0.swap)) }
        }
        return SwapTrend(current: current, change30: change(30), change60: change(60))
    }

    /// La retta degli ultimi 7 giorni sullo spazio libero. Solo se copre almeno 12 ore, se il disco perde davvero
    /// (oltre 1 GB nel periodo) e se il ritmo lo riempie entro 90 giorni.
    func diskForecast(free: Int64, now: Date) -> DiskForecast? {
        let samples = points.filter { !$0.diskFree.isNaN }
        guard let first = samples.first, let last = samples.last, last.minute - first.minute >= 12 * 60 else { return nil }
        // Minimi quadrati su x = giorni, y = byte liberi. Un punto ogni 10 basta e costa poco.
        var n = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
        for (i, p) in samples.enumerated() where i % 10 == 0 || i == samples.count - 1 {
            let x = Double(p.minute - first.minute) / 1440
            let y = Double(p.diskFree)
            n += 1; sx += x; sy += y; sxx += x * x; sxy += x * y
        }
        let denominator = n * sxx - sx * sx
        guard n >= 3, denominator > 0 else { return nil }
        let slope = (n * sxy - sx * sy) / denominator   // byte al giorno
        let span = Double(last.minute - first.minute) / 1440
        guard slope < 0, -slope * span >= 1_000_000_000 else { return nil }
        let days = Double(free) / -slope
        guard days.isFinite, days <= 90 else { return nil }
        return DiskForecast(bytesPerDay: -slope, daysLeft: days)
    }

    /// Valori da disegnare: un punto ogni `step` minuti (media), con i buchi lasciati vuoti (nil).
    func series(_ value: (HistoryPoint) -> Float, minutes: Int, step: Int, now: Date) -> [Double?] {
        let end = HistoryPoint.minute(of: now)
        let start = end - Int32(minutes)
        let count = max(1, minutes / step)
        var sums = [Double](repeating: 0, count: count)
        var counts = [Int](repeating: 0, count: count)
        for p in recent(minutes: minutes, now: now) {
            let v = value(p)
            guard !v.isNaN else { continue }
            let i = min(count - 1, Int(p.minute - start) / step)
            guard i >= 0 else { continue }
            sums[i] += Double(v)
            counts[i] += 1
        }
        return (0..<count).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
    }

    var oldest: Date? { points.first?.date }

    // MARK: File

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("What's Going On", isDirectory: true).appendingPathComponent("history.bin")
    }

    func encoded() -> Data {
        var data = Data(capacity: 8 + points.count * (4 + Self.fields * 4))
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func put(_ v: Float) { put(v.bitPattern) }
        put(Self.magic)
        put(Self.formatVersion)
        for p in points {
            put(p.minute)
            put(p.cpu); put(p.cpuPeak); put(p.memory); put(p.compressed)
            put(p.swap); put(p.diskFree); put(p.pressure); put(p.temperature)
        }
        return data
    }

    init() {}

    init?(data: Data) {
        let record = 4 + Self.fields * 4
        guard data.count >= 8, (data.count - 8) % record == 0 else { return nil }
        let bytes = [UInt8](data)
        func u32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        guard u32(0) == Self.magic, u32(4) == Self.formatVersion else { return nil }
        var points: [HistoryPoint] = []
        points.reserveCapacity((data.count - 8) / record)
        var at = 8
        while at + record <= bytes.count {
            func f(_ i: Int) -> Float { Float(bitPattern: u32(at + 4 + i * 4)) }
            points.append(HistoryPoint(minute: Int32(bitPattern: u32(at)), cpu: f(0), cpuPeak: f(1), memory: f(2),
                                       compressed: f(3), swap: f(4), diskFree: f(5), pressure: f(6), temperature: f(7)))
            at += record
        }
        // In ordine e senza punti più vecchi di 7 giorni (il Mac può essere rimasto spento a lungo).
        let oldest = HistoryPoint.minute(of: Date()) - Int32(Self.retention)
        var last = Int32.min
        self.points = points.filter { p in
            defer { last = max(last, p.minute) }
            return p.minute > oldest && p.minute > last
        }
    }

    static func load(from url: URL = defaultURL) -> LongHistory {
        guard let data = try? Data(contentsOf: url), let history = LongHistory(data: data) else { return LongHistory() }
        return history
    }

    static func save(_ data: Data, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func delete(at url: URL = defaultURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
