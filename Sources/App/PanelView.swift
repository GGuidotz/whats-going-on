// Il pannello che si apre dalla barra dei menu. Le HIG chiedono un menu, salvo funzioni troppo complesse
// (the-menu-bar.md › Menu bar extras): grafici dal vivo e dettagli che si aprono lo sono, quindi è un pannello,
// con le azioni in fondo raggiungibili da tastiera (⌘, e ⌘Q).

import AppKit
import SwiftUI

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PanelView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var prefs: Preferences
    @State private var contentHeight: CGFloat = 420

    private var maxHeight: CGFloat { max(320, (NSScreen.main?.visibleFrame.height ?? 800) - 120) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                SystemPanel(monitor: monitor, advanced: prefs.advanced)
                    .padding(16)
                    .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, maxHeight))
            .onPreferenceChange(HeightKey.self) { contentHeight = $0 }

            Divider()
            HStack {
                SettingsLink {
                    Text(L("Impostazioni…"))
                }
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
                Spacer()
                Button(L("Esci")) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 360)
        .onAppear { monitor.isPanelOpen = true }
        .onDisappear { monitor.isPanelOpen = false }
    }
}
