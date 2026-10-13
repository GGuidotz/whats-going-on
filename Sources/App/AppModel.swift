// What's Going On: cosa succede nel tuo Mac, in una frase. Vive nella barra dei menu (LSUIElement: niente Dock).
// AppModel tiene insieme motore, preferenze, avvisi, aggiornamenti e finestre, e passa al motore le scelte quando
// cambiano. Il ciclo di vita è AppKit (Sources/App/Main.swift): la voce colorata nella barra chiede NSStatusItem.

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let prefs: Preferences
    let monitor = SystemMonitor()
    let delivery = AlertDelivery()
    let updater: Updater
    @Published var settingsTab: SettingsTab = .general

    private let settingsWindow = SettingsWindowController()
    private var bag = Set<AnyCancellable>()

    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    private init() {
        let prefs = Preferences()
        self.prefs = prefs
        updater = Updater(prefs: prefs)
        apply()
        prefs.objectWillChange
            .sink { [unowned self] _ in Task { @MainActor in self.apply() } }
            .store(in: &bag)
        monitor.onAlert = { [weak self] event in
            guard let self else { return }
            delivery.deliver(event, to: prefs.alertDestination)
        }
    }

    func didLaunch() {
        diag(.app, "launched \(appVersion), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        updater.start()
    }

    func showSettings(_ tab: SettingsTab?) {
        if let tab { settingsTab = tab }
        settingsWindow.show(model: self)
    }

    private func apply() {
        monitor.interval = prefs.interval
        monitor.alertSettings = prefs.alerts
        let wantsGPU = prefs.advanced || prefs.enabledModules.contains(.gpu)
        if monitor.includeGPU != wantsGPU {
            monitor.includeGPU = wantsGPU
            monitor.refreshConfiguration()
        }
    }
}

/// Confronto numerico tra versioni ("0.10.0" > "0.9.2").
struct Version: Comparable {
    let parts: [Int]
    init(_ string: String) { parts = string.split(separator: ".").map { Int($0) ?? 0 } }

    static func < (a: Version, b: Version) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }
}
