// Attrezzi › Tastiera: le app che intercettano i tasti adesso (KeyboardTapReader, in Sources/Core). Si legge quando apri
// la scheda e con Aggiorna, mai in continuo. Solo lettura: un tap si toglie chiudendo l'app o togliendole il permesso in
// Impostazioni di Sistema › Privacy e sicurezza.

import AppKit
import SwiftUI

struct KeyboardView: View {
    @State private var taps: [KeyboardTap]?
    @State private var showMacOS = false

    private var report: KeyboardReport? { taps.map(KeyboardReport.init) }
    private var visible: [KeyboardTap] { (taps ?? []).filter { showMacOS || !$0.isMacOS } }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(headline)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentCard(padding: 12)
                HStack {
                    Toggle(L("Mostra anche i servizi di macOS"), isOn: $showMacOS)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button {
                        taps = KeyboardTapReader.read()
                    } label: {
                        Label(L("Aggiorna"), systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(visible) { TapRow(tap: $0) }
                    }
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ToolSection(title: L("Attivo o in ascolto"), symbol: "keyboard") {
                        Text(L("Attivo: l'app può cambiare o bloccare i tasti, quindi ogni tasto aspetta la sua risposta. Se è lenta, scrivere diventa lento per tutte le app. In ascolto: li vede soltanto, non rallenta. Il ritardo è quello misurato da macOS."))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ToolSection(title: L("Come toglierlo"), symbol: "hand.raised") {
                        Text(L("Chiudi l'app, oppure togli il suo permesso in Privacy e sicurezza › Accessibilità o Monitoraggio dell'input. Qui si vede chi intercetta adesso, non chi ha il permesso senza usarlo."))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L("Apri Privacy e sicurezza")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .glassButton()
                        .controlSize(.small)
                    }
                }
                .padding(14)
            }
            .frame(width: 330)
        }
        .onAppear { taps = KeyboardTapReader.read() }
    }

    private var headline: String {
        guard let report else { return L("macOS non ha risposto: riprova con Aggiorna.") }
        let all = report.thirdParty
        if all.isEmpty { return L("Nessuna app installata intercetta la tastiera adesso.") }
        var text = L("%d app intercettano la tastiera, %d in modo attivo.", all.count, report.activeThirdParty.count)
        if let slow = report.slow.first {
            text += " " + L("%@ risponde in %@ ms: si può sentire scrivendo.", slow.name, Format.number(slow.latency ?? 0, digits: 0))
        }
        return text
    }
}

private struct TapRow: View {
    var tap: KeyboardTap

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(path: tap.path)
            VStack(alignment: .leading, spacing: 1) {
                Text(tap.name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Label(tap.active ? L("Attivo") : L("In ascolto"),
                  systemImage: tap.active ? "hand.raised.fill" : "ear")
                .font(.callout)
                .foregroundStyle(tap.isSlow ? Color.orange : Color.secondary)
        }
        .contentCard(padding: 8)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if tap.isMacOS { parts.append(L("servizio di macOS")) }
        if !tap.enabled { parts.append(L("sospeso")) }
        if let latency = tap.latency { parts.append(L("ritardo %@ ms", Format.number(latency, digits: latency < 10 ? 1 : 0))) }
        parts.append(L("PID %d", Int(tap.pid)))
        return parts.joined(separator: " · ")
    }
}

/// L'icona dell'app che contiene il processo, o un'icona generica.
private struct AppIcon: View {
    var path: String?

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }

    private var icon: NSImage {
        if let path, let range = path.range(of: ".app/") {
            return NSWorkspace.shared.icon(forFile: String(path[..<range.lowerBound]) + ".app")
        }
        return NSWorkspace.shared.icon(for: .unixExecutable)
    }
}
