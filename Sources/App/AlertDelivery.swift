// Consegna degli avvisi. Prima scelta: l'isola di Cocaine, con il suo link documentato
// cocaine://alert?from=…&event=done&message=… (lo stesso di `open -g`, senza portare Cocaine in primo piano).
//
// Perché a volte "non arrivano": Cocaine li mostra solo quando sei lontano dal Mac (nessun input da 20 secondi, o
// schermi spenti), salvo "Anche al Mac" acceso in Avvisi AI › Quando; li tace mentre gli avvisi sono in pausa; li fa
// lampeggiare solo con Lampeggio acceso (Sources/AppDelegate.swift di Cocaine, alert()). Altrimenti l'avviso finisce
// solo tra gli avvisi recenti. Quindi: lo mandiamo comunque a Cocaine (resta nella sua cronologia) e, quando Cocaine non
// lo mostrerebbe, arriva anche come notifica di macOS. Se Cocaine è chiuso, solo la notifica.

import AppKit
import CoreGraphics
import UserNotifications

/// Le scelte di Cocaine che decidono se un avviso si vede, lette dalle sue preferenze (l'app non è in sandbox).
struct CocaineAlertSettings: Equatable {
    var whenPresent: Bool
    var flash: Bool
    var pausedUntil: Date?

    static let bundleID = "local.cocaine.toggle"

    static func read() -> CocaineAlertSettings {
        let domain = bundleID as CFString
        _ = CFPreferencesAppSynchronize(domain)
        func value(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, domain) }
        let paused = (value("alertsPausedUntil") as? Date).flatMap { $0 > Date() ? $0 : nil }
        return CocaineAlertSettings(whenPresent: value("alertWhenPresent") as? Bool ?? false,
                                    flash: value("alertFlash") as? Bool ?? true,
                                    pausedUntil: paused)
    }

    /// Cocaine lo mostrerebbe adesso?
    func shows(away: Bool) -> Bool { pausedUntil == nil && flash && (away || whenPresent) }
}

@MainActor
final class AlertDelivery: ObservableObject {
    static var cocaineBundleID: String { CocaineAlertSettings.bundleID }

    @Published private(set) var lastDelivered: String?
    @Published private(set) var cocaine = CocaineAlertSettings.read()
    @Published private(set) var awayTestPending = false

    var cocaineInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.cocaineBundleID) != nil }
    var cocaineRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.cocaineBundleID).isEmpty }

    /// Secondi dall'ultimo tasto, clic o movimento del mouse.
    static var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Rilegge le scelte di Cocaine (all'apertura delle impostazioni e prima di ogni avviso).
    func refreshCocaine() { cocaine = CocaineAlertSettings.read() }

    func deliver(_ event: AlertEvent, to destination: AlertDestination) {
        switch destination {
        case .off:
            return
        case .notifications:
            notify(event, note: L("Inviato come notifica"))
        case .cocaine:
            guard cocaineRunning else {
                notify(event, note: L("Cocaine è chiuso: arrivato come notifica"))
                return
            }
            refreshCocaine()
            sendToCocaine(event.message)
            let away = Self.idleSeconds >= 20
            if cocaine.shows(away: away) {
                lastDelivered = L("Inviato all'isola di Cocaine")
                diag(.alerts, "\(event.kind.rawValue) sent to Cocaine (away: \(away))")
            } else {
                notify(event, note: hiddenReason)
            }
        }
    }

    /// Perché Cocaine non mostrerebbe l'avviso adesso, detto in breve.
    private var hiddenReason: String {
        if cocaine.pausedUntil != nil { return L("Avvisi di Cocaine in pausa: arrivato anche come notifica") }
        if !cocaine.flash { return L("Lampeggio di Cocaine spento: arrivato anche come notifica") }
        return L("Sei al Mac e Cocaine lo mostra solo quando sei via: arrivato anche come notifica")
    }

    func sendTest(to destination: AlertDestination) {
        deliver(AlertEvent(kind: .cpu, message: L("Avviso di prova: se lo leggi, gli avvisi funzionano.")),
                to: destination == .off ? .notifications : destination)
    }

    /// La prova "da lontano": parte tra 25 secondi, il tempo di staccare le mani dal Mac. Così si vede l'isola di Cocaine
    /// anche senza "Anche al Mac".
    func sendTestWhenAway(to destination: AlertDestination) {
        guard !awayTestPending else { return }
        awayTestPending = true
        lastDelivered = L("Non toccare il Mac: l'avviso parte tra 25 secondi.")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            awayTestPending = false
            sendTest(to: destination)
        }
    }

    private func sendToCocaine(_ message: String) {
        var c = URLComponents()
        c.scheme = "cocaine"
        c.host = "alert"
        c.queryItems = [URLQueryItem(name: "from", value: "What's Going On"),
                        URLQueryItem(name: "event", value: "done"),
                        URLQueryItem(name: "message", value: message)]
        guard let url = c.url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            guard let error else { return }
            let text = error.localizedDescription
            Task { @MainActor in diag(.alerts, "cocaine:// link failed: \(text)") }
        }
    }

    private func notify(_ event: AlertEvent, note: String) {
        let title = event.kind.title, body = event.message, id = "wgo.\(event.kind.rawValue)"
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted { Self.post(title: title, body: body, id: id) }
            let failure = error?.localizedDescription
            Task { @MainActor in
                if granted {
                    self.lastDelivered = note
                    diag(.alerts, "\(id) notification posted (\(note))")
                } else {
                    self.lastDelivered = L("macOS non permette le notifiche: Impostazioni di Sistema › Notifiche › What's Going On")
                    diag(.alerts, "notifications not allowed" + (failure.map { ": \($0)" } ?? ""))
                }
            }
        }
    }

    nonisolated private static func post(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = id   // il pulsante dell'attrezzo giusto (AlertActions)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

/// I pulsanti delle notifiche: dall'avviso all'attrezzo che aiuta. Disco quasi pieno → cosa occupa spazio; memoria →
/// le app che pesano; CPU, app che consuma, chip caldo → cosa sta lavorando. Anche il clic sulla notifica apre lì.
enum AlertActions {
    static let open = "open"

    @MainActor
    static func register() {
        let categories = AlertKind.allCases.map { kind in
            UNNotificationCategory(identifier: "wgo.\(kind.rawValue)",
                                   actions: [UNNotificationAction(identifier: open, title: title(kind), options: [.foreground])],
                                   intentIdentifiers: [])
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }

    private static func title(_ kind: AlertKind) -> String {
        switch kind {
        case .disk: L("Vedi cosa occupa spazio")
        case .memory: L("Vedi le app che pesano")
        case .cpu, .process, .temperature: L("Vedi cosa sta lavorando")
        }
    }

    /// L'attrezzo per una notifica (dal suo identificativo "wgo.<tipo>"), nil per le altre.
    @MainActor
    static func handle(_ identifier: String) {
        guard identifier.hasPrefix("wgo."), let kind = AlertKind(rawValue: String(identifier.dropFirst(4))) else { return }
        switch kind {
        case .disk: AppModel.shared.showTools(.space)
        case .memory: AppModel.shared.showTools(.apps, measure: .memory)
        case .cpu, .process, .temperature: AppModel.shared.showTools(.apps, measure: .cpu)
        }
    }
}
