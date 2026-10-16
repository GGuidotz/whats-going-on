// La rete di ogni app. macOS la conta per processo, ma solo nettop la racconta senza privilegi: si chiama
// `nettop -P -L 1` (una lettura dei totali e via) e si fa la differenza con la volta prima.
// Costa un programma esterno, quindi gira solo con l'attrezzo App aperto, al massimo ogni 3 secondi, su una coda sua:
// il campionatore non lo aspetta mai e usa l'ultima lettura pronta.

import Foundation

final class AppNetworkReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.whatsgoingon.nettop", qos: .utility)
    private let lock = NSLock()
    private var rates: [pid_t: (down: Double, up: Double)] = [:]
    private var totals: [pid_t: (down: UInt64, up: UInt64)] = [:]
    private var lastRun: UInt64 = 0
    private var running = false
    /// nettop manca o non risponde: non si riprova.
    private var broken = false

    static let path = "/usr/bin/nettop"

    /// Le velocità dell'ultima lettura, e intanto ne chiede una nuova se è ora. nil se nettop non si può usare.
    func latest() -> [pid_t: (down: Double, up: Double)]? {
        lock.lock()
        defer { lock.unlock() }
        if broken { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        if !running, now - lastRun >= 3_000_000_000 || lastRun == 0 {
            running = true
            queue.async { [weak self] in self?.run() }
        }
        return rates
    }

    /// Finestra chiusa: si dimentica tutto, la prossima volta si riparte da zero.
    func reset() {
        lock.lock()
        rates = [:]
        totals = [:]
        lastRun = 0
        lock.unlock()
    }

    private func run() {
        let output = Self.nettop()
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        defer { lock.unlock() }
        running = false
        guard let output else {
            broken = true
            return
        }
        let current = Self.parse(output)
        let elapsed = lastRun > 0 ? Double(now - lastRun) / 1e9 : 0
        var next: [pid_t: (down: Double, up: Double)] = [:]
        if elapsed > 0 {
            for (pid, total) in current {
                guard let before = totals[pid], total.down >= before.down, total.up >= before.up else { continue }
                let down = Double(total.down - before.down) / elapsed
                let up = Double(total.up - before.up) / elapsed
                if down > 0 || up > 0 { next[pid] = (down, up) }
            }
        }
        rates = next
        totals = current
        lastRun = now
    }

    private static func nettop() -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-P", "-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // Se si blocca, dopo 5 secondi si chiude.
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Righe come "Safari.512,10240,2048,": nome.pid, poi byte ricevuti e inviati da quando il processo è partito.
    static func parse(_ text: String) -> [pid_t: (down: UInt64, up: UInt64)] {
        var result: [pid_t: (down: UInt64, up: UInt64)] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            // Il campo nome.pid: dopo l'ultimo punto un numero, prima almeno una lettera (l'ora, 10:00:00.123, no).
            guard let nameIndex = fields.firstIndex(where: { field in
                guard let dot = field.lastIndex(of: "."), field.index(after: dot) < field.endIndex else { return false }
                return Int32(field[field.index(after: dot)...]) != nil && field[..<dot].contains(where: \.isLetter)
            }) else { continue }
            let field = fields[nameIndex]
            guard let dot = field.lastIndex(of: "."), let pid = pid_t(field[field.index(after: dot)...]) else { continue }
            let numbers = fields[(nameIndex + 1)...].compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count >= 2 else { continue }
            result[pid] = (numbers[0], numbers[1])
        }
        return result
    }
}
