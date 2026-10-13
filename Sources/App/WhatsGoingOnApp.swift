// What's Going On: cosa succede nel tuo Mac, in una frase. Vive nella barra dei menu (LSUIElement: niente Dock).

import Combine
import SwiftUI

/// Tiene insieme motore, preferenze e consegna degli avvisi, e passa al motore le scelte quando cambiano.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let prefs = Preferences()
    let monitor = SystemMonitor()
    let delivery = AlertDelivery()
    private var bag = Set<AnyCancellable>()

    private init() {
        apply()
        prefs.objectWillChange
            .sink { [unowned self] _ in Task { @MainActor in self.apply() } }
            .store(in: &bag)
        monitor.onAlert = { [weak self] event in
            guard let self else { return }
            delivery.deliver(event, to: prefs.alertDestination)
        }
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

@main
struct WhatsGoingOnApp: App {
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(monitor: model.monitor, prefs: model.prefs)
        } label: {
            MenuBarLabel(monitor: model.monitor, prefs: model.prefs)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(prefs: model.prefs, monitor: model.monitor, delivery: model.delivery)
        }
    }
}
