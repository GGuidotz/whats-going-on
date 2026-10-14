// Mole (github.com/tw93/Mole, GPL-3.0) dentro l'app: lo chiamiamo come programma a parte, non ne copiamo il codice.
// Senza terminale Mole lavora da solo: `mo clean` pulisce cache, log e file temporanei dell'utente e salta quelli di
// sistema (chiedono la password); `mo optimize` chiede la password con una finestra sua quando serve. Prima si guarda
// sempre l'anteprima (--dry-run): Mole cancella per sempre, non nel Cestino (sono cose che si ricreano).
// Nessun lavoro finché non premi un pulsante; l'uscita si legge riga per riga, senza colori.

import AppKit
import Foundation

@MainActor
final class MoleRunner: ObservableObject {
    enum Command: String {
        case clean, optimize, install
    }

    struct Run: Equatable {
        var command: Command
        var dryRun: Bool
    }

    struct Outcome: Equatable {
        var run: Run
        var succeeded: Bool
    }

    @Published private(set) var current: Run?
    @Published private(set) var last: Outcome?
    @Published private(set) var lines: [String] = []
    /// La riga con il totale ("Potential space: 3.2GB", "Tracked cleanup: …").
    @Published private(set) var summary: String?
    @Published private(set) var executable: String? = MoleRunner.locate()

    private var process: Process?
    private var partial = ""

    var isInstalled: Bool { executable != nil }
    nonisolated static var brew: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// L'elenco completo dell'ultima anteprima di `mo clean`.
    nonisolated static var previewList: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.config/mole/clean-list.txt")
    }

    nonisolated static func locate() -> String? {
        ["/opt/homebrew/bin/mo", "/usr/local/bin/mo", NSHomeDirectory() + "/.local/bin/mo"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func refresh() { executable = Self.locate() }

    func run(_ command: Command, dryRun: Bool) {
        guard process == nil else { return }
        let tool: String
        var arguments: [String]
        switch command {
        case .install:
            guard let brew = Self.brew else { return }
            tool = brew
            arguments = ["install", "mole"]
        case .clean, .optimize:
            guard let mo = Self.locate() else { refresh(); return }
            tool = mo
            arguments = [command.rawValue]
            if dryRun { arguments.append("--dry-run") }
        }

        lines = []
        summary = nil
        partial = ""
        let run = Run(command: command, dryRun: dryRun)
        current = run

        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.append(text) } }
        }
        p.terminationHandler = { [weak self] proc in
            reader.readabilityHandler = nil
            let rest = String(decoding: reader.readDataToEndOfFile(), as: UTF8.self)
            let status = proc.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.append(rest)
                    self?.finish(run, status: status)
                }
            }
        }
        do {
            try p.run()
            process = p
            diag(.app, "mole \(arguments.joined(separator: " ")) started")
        } catch {
            lines = [error.localizedDescription]
            current = nil
            last = Outcome(run: run, succeeded: false)
        }
    }

    func stop() {
        process?.terminate()
    }

    private func finish(_ run: Run, status: Int32) {
        if !partial.isEmpty { add(partial) }
        partial = ""
        process = nil
        current = nil
        last = Outcome(run: run, succeeded: status == 0)
        if run.command == .install { refresh() }
        diag(.app, "mole \(run.command.rawValue)\(run.dryRun ? " --dry-run" : "") ended with \(status)")
    }

    private static let ansi = try? NSRegularExpression(pattern: "\u{1B}(\\[[0-9;?]*[ -/]*[@-~]|\\][^\u{07}]*\u{07}|[()][A-Z0-9])")

    private func append(_ text: String) {
        guard !text.isEmpty else { return }
        let chunks = (partial + text).components(separatedBy: "\n")
        partial = chunks.last ?? ""
        for chunk in chunks.dropLast() { add(chunk) }
    }

    /// Una riga pulita: senza colori e, per gli indicatori che si riscrivono (\r), solo l'ultima versione.
    private func add(_ raw: String) {
        var line = raw.components(separatedBy: "\r").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        if let ansi = Self.ansi {
            line = ansi.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
        }
        line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        if line.contains("Potential space:") || line.contains("Tracked cleanup:") || line.hasPrefix("Free space:") {
            summary = line
        }
        lines.append(line)
        if lines.count > 600 { lines.removeFirst(lines.count - 600) }
    }
}
