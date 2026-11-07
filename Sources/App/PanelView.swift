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
            SystemPanel(monitor: model.monitor, advanced: prefs.advanced, tools: tools,
                        belowSummary: AnyView(WhySlowBox(model: model, advice: model.diagnosisAdvice, prefs: prefs,
                                                         openTool: openTool)))
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
        .onDisappear { model.clearDiagnosis() }   // riaprendo, una risposta vecchia non deve sembrare di adesso
    }

    /// Da una causa di "Perché è lento?" all'attrezzo che la sistema.
    private func openTool(_ tool: Cause.Tool) {
        close()
        switch tool {
        case .space: model.showTools(.space)
        case .memory: model.showTools(.apps, measure: .memory)
        case .cpu: model.showTools(.apps, measure: .cpu)
        case .startup: model.showTools(.startup)
        case .keyboard: model.showTools(.keyboard)
        }
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

/// "Perché è lento?": un pulsante sotto la frase; premuto, le cause trovate dalle regole e, se accesa e disponibile,
/// la riscrittura di Apple Intelligence.
private struct WhySlowBox: View {
    @ObservedObject var model: AppModel
    @ObservedObject var advice: AdviceModel
    @ObservedObject var prefs: Preferences
    var openTool: (Cause.Tool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    model.diagnose()
                } label: {
                    Label(model.diagnosis == nil ? L("Perché è lento?") : L("Controlla di nuovo"),
                          systemImage: "stethoscope")
                }
                .glassButton()
                .controlSize(.small)
                if model.diagnosis != nil {
                    Button(L("Chiudi")) { model.clearDiagnosis() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            if let diagnosis = model.diagnosis {
                DiagnosisView(diagnosis: diagnosis, openTool: openTool)
                if prefs.intelligence, AdviceModel.unavailableReason == nil, !diagnosis.causes.isEmpty {
                    intelligence(diagnosis)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func intelligence(_ diagnosis: Diagnosis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    advice.ask(.slow, context: diagnosis.plainText)
                } label: {
                    Label(L("Spiegamelo in parole semplici"), systemImage: "sparkles")
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(advice.state == .working)
                if advice.state == .working { ProgressView().controlSize(.mini) }
            }
            switch advice.state {
            case .answer(let lines):
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(L("Scritto da Apple Intelligence sul Mac a partire dalle cause qui sopra: controlla prima di agire."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            case .idle, .working:
                EmptyView()
            }
        }
    }
}
