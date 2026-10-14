// Il pannello che si apre dalla barra dei menu. Le HIG chiedono un menu, salvo funzioni troppo complesse
// (the-menu-bar.md › Menu bar extras): grafici dal vivo e dettagli che si aprono lo sono, quindi è un pannello.
// È un popover: su macOS 26 il vetro lo mette il sistema. In fondo, i controlli che galleggiano: pulsanti di vetro
// (Impostazioni ⌘, ed Esci ⌘Q) e, quando c'è, la nuova versione, in una barra sotto cui il contenuto scorre e sfuma.

import AppKit
import SwiftUI

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct FooterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var updater: Updater
    var close: () -> Void
    @State private var contentHeight: CGFloat = 420
    @State private var footerHeight: CGFloat = 50

    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model
        prefs = model.prefs
        updater = model.updater
        self.close = close
    }

    private var maxHeight: CGFloat { max(320, (NSScreen.main?.visibleFrame.height ?? 800) - 140) }

    var body: some View {
        ScrollView {
            SystemPanel(monitor: model.monitor, advanced: prefs.advanced, tools: tools)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
        }
        .scrollBounceBehavior(.basedOnSize)
        .floatingBottomBar {
            footer.background(GeometryReader { Color.clear.preference(key: FooterHeightKey.self, value: $0.size.height) })
        }
        .frame(width: 360, height: min(contentHeight + footerHeight, maxHeight))
        .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
        .onPreferenceChange(FooterHeightKey.self) { if $0 > 0 { footerHeight = $0 } }
    }

    /// Gli attrezzi si aprono in una finestra loro: il pannello si chiude.
    private var tools: PanelTools {
        PanelTools(space: { close(); model.showTools(.space) },
                   memory: { close(); model.showTools(.apps, measure: .memory) },
                   cpu: { close(); model.showTools(.apps, measure: .cpu) })
    }

    private var footer: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    close()
                    model.showSettings(nil)
                } label: {
                    Label(L("Impostazioni"), systemImage: "gearshape")
                }
                .keyboardShortcut(",")
                .glassButton()
                .help(L("Impostazioni") + " (⌘,)")

                Button {
                    close()
                    model.showTools(.space)
                } label: {
                    Label(L("Attrezzi"), systemImage: "wrench.and.screwdriver")
                        .labelStyle(.iconOnly)
                }
                .keyboardShortcut("t")
                .glassButton()
                .help(L("Attrezzi: spazio, memoria e CPU") + " (⌘T)")
                .accessibilityLabel(L("Attrezzi"))

                if case .available(let version) = updater.state {
                    Button {
                        close()
                        model.showSettings(.updates)
                    } label: {
                        Label(L("Versione %@", version), systemImage: "arrow.down.circle.fill")
                    }
                    .glassProminentButton()
                    .tint(Palette.calm)
                    .help(L("È disponibile una nuova versione"))
                }

                Spacer(minLength: 0)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label(L("Esci"), systemImage: "power")
                }
                .keyboardShortcut("q")
                .glassButton()
                .help(L("Esci da What's Going On") + " (⌘Q)")
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.regular)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
