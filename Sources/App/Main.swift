// Avvio dell'app, senza il ciclo di vita di SwiftUI: la voce nella barra è un NSStatusItem (Sources/App/StatusItem.swift)
// e le impostazioni una finestra nostra (Sources/App/SettingsWindow.swift). Il menu principale non si vede (l'app non
// ha Dock né barra propria) ma porta le scorciatoie: ⌘, ⌘W ⌘Q e taglia, copia e incolla nei campi di testo.

import AppKit
import Combine
import UserNotifications

@main
enum WhatsGoingOnMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            app.delegate = AppDelegate.shared
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = AppDelegate()

    private var statusItem: StatusItemController?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        UNUserNotificationCenter.current().delegate = self
        NSApp.mainMenu = MainMenu.make()
        model.prefs.$language.dropFirst().receive(on: RunLoop.main)
            .sink { _ in NSApp.mainMenu = MainMenu.make() }
            .store(in: &bag)
        statusItem = StatusItemController(model: model)
        model.didLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Aprire l'app già aperta (dal Finder o da Spotlight) apre il pannello: è lì che si vede cosa succede.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.showPanel()
        return false
    }

    @objc func openSettings(_ sender: Any?) { AppModel.shared.showSettings(nil) }
    @objc func showAbout(_ sender: Any?) { AboutPanel.show() }

    /// Le notifiche si vedono anche mentre l'app è in primo piano (per esempio con le impostazioni aperte).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: L("Informazioni su What's Going On"), action: #selector(AppDelegate.showAbout(_:)),
                    keyEquivalent: "").target = AppDelegate.shared
        app.addItem(.separator())
        app.addItem(withTitle: L("Impostazioni…"), action: #selector(AppDelegate.openSettings(_:)),
                    keyEquivalent: ",").target = AppDelegate.shared
        app.addItem(.separator())
        app.addItem(withTitle: L("Esci da What's Going On"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: app, title: "What's Going On")

        let file = NSMenu(title: L("Archivio"))
        file.addItem(withTitle: L("Chiudi"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: file, title: file.title)

        let edit = NSMenu(title: L("Modifica"))
        edit.addItem(withTitle: L("Annulla"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("Ripeti"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L("Taglia"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("Copia"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Incolla"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Seleziona tutto"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: edit.title)
        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
