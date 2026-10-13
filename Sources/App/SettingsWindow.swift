// La finestra delle impostazioni: una finestra AppKit con dentro SwiftUI, perché senza il ciclo di vita di SwiftUI
// la scena Settings non c'è. Barra del titolo trasparente: la barra delle schede di vetro galleggia sopra il contenuto.

import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, menuBar, alerts, updates, feedback
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("Generale")
        case .menuBar: L("Barra dei menu")
        case .alerts: L("Avvisi")
        case .updates: L("Aggiornamenti")
        case .feedback: L("Feedback")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .alerts: "bell.badge"
        case .updates: "arrow.down.circle"
        case .feedback: "bubble.left.and.text.bubble.right"
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: SettingsView.size.width, height: SettingsView.size.height))
            w.center()
            window = w
        }
        window?.title = L("Impostazioni di What's Going On")   // per Mission Control e VoiceOver, anche dopo un cambio di lingua
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// La barra delle schede: un controllo che galleggia, quindi di vetro. ⌘1…⌘5 per passare da una scheda all'altra.
struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element) { index, tab in
                    let selected = selection == tab
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .frame(height: 18)
                            Text(tab.title)
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(width: 92, height: 44)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(5)
            .glassSurface(in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
    }
}
