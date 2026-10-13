// La voce nella barra dei menu e il suo pannello. NSStatusItem invece di MenuBarExtra: MenuBarExtra disegna l'etichetta
// come immagine modello (un colore solo), mentre la barra di What's Going On è colorata (MenuBarRenderer).
// Clic: apre o chiude il pannello (un popover: su macOS 26 è di vetro). Clic destro o ctrl-clic: un menu breve.

import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    /// Un clic sulla voce mentre il pannello è aperto lo chiude (popover transitorio) prima che arrivi il clic: senza
    /// questo, il pannello si chiuderebbe e si riaprirebbe subito.
    private var lastClose = Date.distantPast
    /// Ciò che è disegnato adesso: se la lettura nuova dà la stessa immagine, non si ridisegna nulla (meno CPU).
    private var drawn: Drawn?
    private var lastRedraw = Date.distantPast

    private struct Drawn: Equatable {
        var entries: [MenuBarEntry]
        var dark: Bool
        var layout: MenuBarLayout
        var scale: ColorScale
        var tip: String
    }

    init(model: AppModel) {
        self.model = model
        super.init()
        item.autosaveName = "WhatsGoingOn"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            // Barra chiara o scura (dipende anche dallo sfondo della scrivania): ridisegna subito con i colori giusti.
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.redraw() } }
            }
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // Ridisegna a ogni lettura e quando cambiano le scelte (dopo il cambio: receive(on:) aspetta il giro dopo).
        model.monitor.$snapshot.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redraw() }
            .store(in: &bag)
        model.prefs.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redraw() }
            .store(in: &bag)
        // La barra torna visibile (uscita dallo schermo intero, barra che ricompare): subito i valori di adesso.
        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self, let window = note.object as? NSWindow, window === self.item.button?.window,
                      self.isVisible else { return }
                self.redraw()
            }
            .store(in: &bag)
        redraw()
    }

    /// La voce si vede: no con un'app a schermo intero o con la barra dei menu nascosta.
    private var isVisible: Bool { item.button?.window?.occlusionState.contains(.visible) ?? true }

    private var isDark: Bool {
        item.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func redraw() {
        guard let button = item.button else { return }
        // Barra nascosta: non si disegna. Un controllo ogni 30 s resta, nel caso macOS non avvisi del ritorno.
        guard isVisible || Date().timeIntervalSince(lastRedraw) >= 30 else { return }
        lastRedraw = Date()
        let prefs = model.prefs, monitor = model.monitor
        let entries = MenuBarRenderer.entries(prefs.visibleModules, snapshot: monitor.snapshot, history: monitor.history,
                                              graphs: prefs.style == .graphs)
        let state = Drawn(entries: entries, dark: isDark, layout: prefs.menuBarLayout, scale: prefs.colorScale,
                          tip: model.monitor.summary.title)
        guard state != drawn else { return }
        drawn = state
        if entries.isEmpty {
            let symbol = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "What's Going On")
            symbol?.isTemplate = true
            button.image = symbol
            button.toolTip = "What's Going On"
            button.setAccessibilityLabel("What's Going On")
        } else {
            button.image = MenuBarRenderer.image(entries, dark: state.dark, layout: state.layout, scale: state.scale)
            let spoken = MenuBarRenderer.spokenLabel(entries)
            button.toolTip = state.tip + "\n" + spoken
            button.setAccessibilityLabel("What's Going On: " + spoken)
        }
    }

    // MARK: - Clic

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if popover.isShown {
            closePanel()
        } else if Date().timeIntervalSince(lastClose) > 0.35 {
            showPanel()
        }
    }

    func showPanel() {
        guard let button = item.button, !popover.isShown else { return }
        // Il contenuto nasce all'apertura e se ne va alla chiusura: a pannello chiuso nessuna vista lavora.
        let host = NSHostingController(rootView: PanelView(model: model, close: { [weak self] in self?.closePanel() }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePanel() {
        if popover.isShown { popover.performClose(nil) }
    }

    private func showMenu() {
        closePanel()
        let menu = NSMenu()
        menu.addItem(withTitle: L("Apri il pannello"), action: #selector(openPanelFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Impostazioni…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L("Novità e aggiornamenti…"), action: #selector(openUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Invia un feedback…"), action: #selector(openFeedback), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Esci da What's Going On"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)   // apre il menu sotto la voce, come le voci di sistema
        item.menu = nil                  // e il clic sinistro torna al pannello
    }

    @objc private func openPanelFromMenu() { showPanel() }
    @objc private func openSettings() { model.showSettings(.general) }
    @objc private func openUpdates() { model.showSettings(.updates) }
    @objc private func openFeedback() { model.showSettings(.feedback) }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidShow(_ notification: Notification) {
        MainActor.assumeIsolated { model.monitor.isPanelOpen = true }
    }

    nonisolated func popoverWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { lastClose = Date() }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            model.monitor.isPanelOpen = false
            popover.contentViewController = nil
        }
    }
}
