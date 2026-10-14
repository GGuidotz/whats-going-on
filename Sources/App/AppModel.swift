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
    /// Mole (Attrezzi): vive con l'app, così un comando avviato finisce anche se chiudi la finestra.
    let mole = MoleRunner()
    @Published var settingsTab: SettingsTab = .general
    /// Apre il pannello della barra (lo imposta AppDelegate): la guida ci porta l'utente alla fine.
    var openPanel: (() -> Void)?

    private let settingsWindow = SettingsWindowController()
    private let onboardingWindow = OnboardingWindowController()
    private let toolsWindow = ToolsWindowController()
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
        watchAway()
    }

    /// Schermi spenti o Mac bloccato: il motore rallenta (Sources/Core/SystemMonitor.swift).
    private func watchAway() {
        var asleep = false, locked = false
        let update = { [weak self] in MainActor.assumeIsolated { self?.monitor.isAway = asleep || locked } }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { _ in asleep = true; update() }.store(in: &bag)
        workspace.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { _ in asleep = false; update() }.store(in: &bag)
        let distributed = DistributedNotificationCenter.default()
        distributed.publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .receive(on: RunLoop.main)
            .sink { _ in locked = true; update() }.store(in: &bag)
        distributed.publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .receive(on: RunLoop.main)
            .sink { _ in locked = false; update() }.store(in: &bag)
    }

    func didLaunch() {
        diag(.app, "launched \(appVersion), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        updater.start()
    }

    func showSettings(_ tab: SettingsTab?) {
        if let tab { settingsTab = tab }
        settingsWindow.show(model: self)
    }

    /// La guida dei primi passi: da sola al primo avvio, poi da Impostazioni › Generale.
    func showOnboarding() {
        onboardingWindow.show(model: self)
    }

    /// Gli attrezzi: Spazio (cosa occupa il disco) o App (memoria e CPU). Dal pannello, dagli avvisi e dal menu.
    func showTools(_ tab: ToolsTab, measure: AppsView.Measure? = nil) {
        toolsWindow.show(model: self, tab: tab, measure: measure)
    }

    private func apply() {
        monitor.interval = prefs.interval
        monitor.alertSettings = prefs.alerts
        // Solo ciò che qualcuno guarda: la barra, gli avvisi accesi, la modalità avanzata.
        var needs = monitor.needs
        needs.gpu = prefs.advanced || prefs.enabledModules.contains(.gpu)
        needs.temperature = prefs.enabledModules.contains(.temperature) || prefs.alerts[.temperature].enabled
        needs.temperatureInterval = prefs.temperatureInterval
        needs.power = prefs.enabledModules.contains(.power)
        needs.allSensors = prefs.advanced
        monitor.needs = needs
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
