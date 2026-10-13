// Le scelte di chi usa l'app, salvate in UserDefaults. Predefiniti sensati: si usa senza toccare nulla.

import Foundation

enum MenuBarModule: String, CaseIterable, Codable, Identifiable {
    case cpu, memory, network, temperature, gpu, disk, power
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: L("CPU")
        case .memory: L("Memoria")
        case .network: L("Rete")
        case .temperature: L("Temperatura")
        case .gpu: L("GPU")
        case .disk: L("Disco")
        case .power: L("Consumo")
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        case .temperature: "thermometer.medium"
        case .gpu: "square.stack.3d.up"
        case .disk: "internaldrive"
        case .power: "bolt"
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Codable, Identifiable {
    case values, graphs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .values: L("Numeri")
        case .graphs: L("Grafici")
        }
    }
}

enum AlertDestination: String, CaseIterable, Codable, Identifiable {
    case cocaine, notifications, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cocaine: L("Isola di Cocaine")
        case .notifications: L("Notifiche di macOS")
        case .off: L("Nessuno")
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var moduleOrder: [MenuBarModule] { didSet { save(moduleOrder, "moduleOrder") } }
    @Published var enabledModules: Set<MenuBarModule> { didSet { save(enabledModules, "enabledModules") } }
    @Published var style: MenuBarStyle { didSet { save(style, "style") } }
    @Published var interval: Double { didSet { defaults.set(interval, forKey: "interval") } }
    @Published var advanced: Bool { didSet { defaults.set(advanced, forKey: "advanced") } }
    @Published var language: AppLanguage {
        didSet { Localization.language = language; save(language, "language") }
    }
    @Published var alerts: AlertSettings { didSet { save(alerts, "alerts") } }
    @Published var alertDestination: AlertDestination { didSet { save(alertDestination, "alertDestination") } }

    init() {
        func load<T: Decodable>(_ key: String, _ fallback: T) -> T {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
            return value
        }
        var order = load("moduleOrder", MenuBarModule.allCases)
        order += MenuBarModule.allCases.filter { !order.contains($0) }   // moduli nuovi in coda
        moduleOrder = order
        enabledModules = load("enabledModules", [.cpu, .memory, .network])
        style = load("style", MenuBarStyle.values)
        interval = UserDefaults.standard.object(forKey: "interval") as? Double ?? 2
        advanced = UserDefaults.standard.bool(forKey: "advanced")
        language = load("language", AppLanguage.system)
        alerts = load("alerts", AlertSettings())
        alertDestination = load("alertDestination", AlertDestination.cocaine)
        Localization.language = language
    }

    /// I moduli accesi, nell'ordine scelto.
    var visibleModules: [MenuBarModule] { moduleOrder.filter { enabledModules.contains($0) } }

    func move(_ module: MenuBarModule, by offset: Int) {
        guard let i = moduleOrder.firstIndex(of: module) else { return }
        let j = i + offset
        guard moduleOrder.indices.contains(j) else { return }
        moduleOrder.swapAt(i, j)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
