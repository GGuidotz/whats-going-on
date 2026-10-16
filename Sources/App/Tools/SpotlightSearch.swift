// Attrezzi › Spazio › Cerca su tutto il Mac: i file per nome con Spotlight, anche senza aver letto il disco, dal più
// grande. Spotlight ha già l'indice: la ricerca costa poco e si ferma appena ha raccolto i risultati (niente
// aggiornamenti dal vivo). Le cartelle che Spotlight non indicizza (escluse in Impostazioni, Libreria) restano fuori.

import AppKit
import SwiftUI

@MainActor
final class SpotlightSearch: ObservableObject {
    @Published var text = ""
    @Published private(set) var results: [FoundItem] = []
    @Published private(set) var searching = false
    @Published private(set) var searched = false

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    static let limit = 100

    func run() {
        stop()
        let term = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
        guard term.count >= 2 else {
            results = []
            searched = false
            return
        }
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(term)*")
        q.searchScopes = [NSMetadataQueryLocalComputerScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSSizeKey, ascending: false)]
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        query = q
        searching = true
        diag(.app, "spotlight search started")
        if !q.start() {
            searching = false
            stop()
        }
    }

    private func finish() {
        guard let q = query else { return }
        q.disableUpdates()
        var found: [FoundItem] = []
        for i in 0..<min(q.resultCount, Self.limit) {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value ?? 0
            let date = item.value(forAttribute: "kMDItemLastUsedDate") as? Date
                ?? item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            found.append(FoundItem(path: path, size: size, date: date))
        }
        results = found
        searching = false
        searched = true
        stop()
    }

    func stop() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func remove(_ paths: Set<String>) {
        results.removeAll { paths.contains($0.path) }
    }
}

struct SpotlightBox: View {
    @ObservedObject var search: SpotlightSearch
    @ObservedObject var space: SpaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField(L("Nome del file"), text: $search.text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search.run() }
                Button(L("Cerca")) { search.run() }
                    .glassButton()
                    .disabled(search.text.trimmingCharacters(in: .whitespaces).count < 2)
            }
            .controlSize(.small)
            if search.searching {
                ProgressView().controlSize(.small)
            } else if search.searched && search.results.isEmpty {
                Text(L("Nessun file con questo nome.")).font(.caption).foregroundStyle(.secondary)
            } else if !search.results.isEmpty {
                Text(search.results.count >= SpotlightSearch.limit
                     ? L("I %d più grandi, dal più grande.", SpotlightSearch.limit)
                     : L("%d trovati, dal più grande.", search.results.count))
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(search.results) { item in
                            HStack(spacing: 6) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                                    .resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                                Text(item.name).lineLimit(1).truncationMode(.middle).help(item.path)
                                Spacer(minLength: 4)
                                Text(Format.diskBytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                                Button { space.reveal(item.path) } label: { Image(systemName: "magnifyingglass") }
                                    .buttonStyle(.borderless)
                                    .help(L("Mostra nel Finder"))
                                    .accessibilityLabel(L("Mostra %@ nel Finder", item.name))
                                if space.canTrash(item.path) {
                                    Button {
                                        space.trash([item]) { moved in search.remove(moved) }
                                    } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                        .help(L("Sposta nel Cestino"))
                                        .accessibilityLabel(L("Sposta %@ nel Cestino", item.name))
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            Text(L("Cerca con Spotlight su tutto il Mac, anche senza leggere il disco. Le cartelle escluse da Spotlight restano fuori."))
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .contentCard(padding: 10)
        .onDisappear { search.stop() }
    }
}
