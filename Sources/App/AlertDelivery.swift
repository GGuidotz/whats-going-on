// Consegna degli avvisi. Prima scelta: l'isola di Cocaine, con il suo link documentato
// cocaine://alert?from=…&event=done&message=… (lo stesso di `open -g`, senza portare Cocaine in primo piano).
// Se Cocaine non è aperto, o hai scelto le notifiche, arriva una notifica di macOS.

import AppKit
import UserNotifications

@MainActor
final class AlertDelivery: ObservableObject {
    static let cocaineBundleID = "local.cocaine.toggle"

    @Published private(set) var lastDelivered: String?

    var cocaineInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.cocaineBundleID) != nil }
    var cocaineRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.cocaineBundleID).isEmpty }

    func deliver(_ event: AlertEvent, to destination: AlertDestination) {
        switch destination {
        case .off:
            return
        case .cocaine where cocaineRunning:
            sendToCocaine(event.message)
            lastDelivered = L("Inviato all'isola di Cocaine")
        case .cocaine, .notifications:
            notify(event)
            lastDelivered = L("Inviato come notifica")
        }
    }

    func sendTest(to destination: AlertDestination) {
        deliver(AlertEvent(kind: .cpu, message: L("Avviso di prova: se lo leggi, gli avvisi funzionano.")),
                to: destination == .off ? .notifications : destination)
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
        NSWorkspace.shared.open(url, configuration: configuration) { _, _ in }
    }

    private var authorizationRequested = false

    private func notify(_ event: AlertEvent) {
        let title = event.kind.title, body = event.message, id = "wgo.\(event.kind.rawValue)"
        if authorizationRequested {
            Self.post(title: title, body: body, id: id)
        } else {
            authorizationRequested = true
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted { Self.post(title: title, body: body, id: id) }
            }
        }
    }

    nonisolated private static func post(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
