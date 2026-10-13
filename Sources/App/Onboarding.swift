// La guida dei primi passi: quattro schermate brevi al primo avvio (e da Impostazioni › Generale). Cosa fa l'app,
// cosa mostrare nella barra, dove mandare gli avvisi, come si usa. Ogni scelta qui è la stessa delle impostazioni,
// quindi si può saltare tutto: chiudere la finestra va bene quanto arrivare in fondo.
// HIG (onboarding.md): breve, si impara usando, i permessi si chiedono nel momento in cui servono e spiegando perché.

import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let view = OnboardingView(model: model, prefs: model.prefs, monitor: model.monitor) { [weak self] in
                self?.window?.performClose(nil)
                model.openPanel?()
            }
            let w = TranslucentWindow.make(view, size: OnboardingView.size)
            w.delegate = self
            window = w
        }
        window?.title = L("Benvenuto in What's Going On")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Chiusa in qualunque modo, la guida è vista: non torna da sola. Via anche le viste, come per le impostazioni.
    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                AppModel.shared.prefs.onboardingDone = true
                self?.window?.contentViewController = nil
                self?.window = nil
            }
        }
    }
}

struct OnboardingView: View {
    static let size = CGSize(width: 520, height: 580)

    var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var monitor: SystemMonitor
    var finish: () -> Void

    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: menuBar
                case 2: alerts
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 44)
            .transition(.opacity)
            .id(step)

            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .id(prefs.language)
    }

    // MARK: - Passi

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(L("Benvenuto in What's Going On"))
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)
            Text(L("Ti dice cosa succede nel Mac, in una frase, dalla barra dei menu. Pesa pochissimo: legge solo ciò che mostri."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            MenuBarPreview(monitor: monitor, prefs: prefs)
                .padding(.top, 8)
            Text(L("Eccolo dal vivo: in alto a destra trovi la stessa voce."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var menuBar: some View {
        StepPage(symbol: "menubar.rectangle", title: L("Cosa vedere nella barra"),
                 text: L("Scegli le misure. Il colore va dal verde al rosso con il carico, il numero resta sempre scritto.")) {
            MenuBarPreview(monitor: monitor, prefs: prefs)
                .frame(maxWidth: .infinity)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 10) {
                ForEach(prefs.moduleOrder) { module in
                    Toggle(isOn: Binding(
                        get: { prefs.enabledModules.contains(module) },
                        set: { if $0 { prefs.enabledModules.insert(module) } else { prefs.enabledModules.remove(module) } }
                    )) {
                        Label(module.title, systemImage: module.symbol)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.top, 4)
            Picker(L("Colori"), selection: $prefs.colorScale.kind) {
                ForEach(ColorScale.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)
            Footnote(L("Temperatura, GPU e consumo compaiono solo se questo Mac li fornisce. Ordine, spazi e colori si cambiano in Impostazioni › Barra dei menu."))
        }
    }

    private var alerts: some View {
        StepPage(symbol: "bell.badge", title: L("Avvisi"),
                 text: L("Quando qualcosa resta troppo alto (CPU, memoria, disco, temperatura, un'app che consuma), te lo dico. Una volta sola, e solo se dura.")) {
            Picker(L("Mostra gli avvisi in"), selection: $prefs.alertDestination) {
                ForEach(AlertDestination.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            if prefs.alertDestination == .cocaine, !model.delivery.cocaineInstalled {
                Footnote(L("Cocaine non è installato: finché non c'è, gli avvisi arrivano come notifiche."))
            }
            if prefs.alertDestination != .off {
                NotificationPermission()
                    .padding(.top, 4)
            }
            Footnote(L("Soglie e durate si cambiano in Impostazioni › Avvisi."))
        }
    }

    private var ready: some View {
        StepPage(symbol: "checkmark.circle", title: L("Tutto pronto"),
                 text: L("Ecco come si usa.")) {
            Tip(symbol: "cursorarrow.click", text: L("Clic sulla voce nella barra: il pannello, con la frase e i dettagli. Clic su una riga per aprirla."))
            Tip(symbol: "cursorarrow.click.2", text: L("Clic destro (o ctrl-clic): impostazioni, novità, feedback, esci."))
            Tip(symbol: "command", text: L("Nel pannello, ⌘, apre le impostazioni e ⌘Q chiude l'app."))
            Tip(symbol: "leaf", text: L("A pannello chiuso legge solo ciò che serve: in Impostazioni › Generale vedi quanto pesa."))
            Toggle(L("Apri all'accesso"), isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.set($0) }
            ))
            .toggleStyle(.switch)
            .padding(.top, 8)
        }
    }

    // MARK: - In fondo

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.primary.opacity(0.75) : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Passo %d di %d", step + 1, steps))

            Spacer()

            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    if step > 0 {
                        Button(L("Indietro")) { go(step - 1) }
                            .glassButton()
                            .keyboardShortcut(.cancelAction)
                    }
                    Button(step == steps - 1 ? L("Inizia") : L("Avanti")) {
                        if step == steps - 1 { finish() } else { go(step + 1) }
                    }
                    .glassProminentButton()
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func go(_ next: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = min(max(0, next), steps - 1) }
    }
}

/// Una pagina della guida: simbolo, titolo, una frase, poi il contenuto.
private struct StepPage<Content: View>: View {
    var symbol: String
    var title: String
    var text: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.semibold))
                .fontDesign(.rounded)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Tip: View {
    var symbol: String
    var text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
        }
        .font(.body)
    }
}

private struct Footnote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Il permesso per le notifiche, chiesto qui perché serve agli avvisi, con lo stato scritto accanto.
private struct NotificationPermission: View {
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        HStack(spacing: 10) {
            switch status {
            case .authorized, .provisional:
                Label(L("Notifiche consentite"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.calm)
            case .denied:
                Label(L("Notifiche negate: Impostazioni di Sistema › Notifiche › What's Going On"),
                      systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            default:
                Button(L("Consenti le notifiche")) { request() }
                    .glassButton()
                Text(L("Servono quando Cocaine non può mostrare l'avviso."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }

    private func request() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refresh()
        }
    }
}
