// Attrezzi › Spazio › Elenco: le voci della cartella mostrata in una tabella, come il Finder in vista elenco.
// Si ordina per colonna, si entra nelle cartelle con doppio clic e si spuntano più voci per metterle nel Cestino
// insieme (sempre con conferma). Le spunte restano anche cambiando cartella, così si raccoglie da più posti.

import AppKit
import SwiftUI

struct SpaceRow: Identifiable {
    var id: Int
    var name: String
    var size: Int64
    var items: Int
    /// distantPast se non si sa: così la colonna si ordina lo stesso.
    var modified: Date
    var kind: FileKind
    var kindTitle: String
    var isDirectory: Bool
    var isSynthetic: Bool
    var canTrash: Bool
}

struct SpaceTableView: View {
    @ObservedObject var space: SpaceModel
    var tree: DiskTree
    @State private var order = [KeyPathComparator(\SpaceRow.size, order: .reverse)]

    private var rows: [SpaceRow] {
        tree[space.focus].children.compactMap { i -> SpaceRow? in
            let node = tree[i]
            if let filter = space.kindFilter, node.kind != filter { return nil }
            let path = tree.path(of: i)
            return SpaceRow(id: i, name: node.name, size: node.size, items: node.items,
                            modified: node.modified ?? .distantPast, kind: node.kind,
                            kindTitle: node.isSynthetic ? L("Piccoli elementi sommati") : node.kind.title,
                            isDirectory: node.isDirectory && !node.children.isEmpty, isSynthetic: node.isSynthetic,
                            canTrash: path.map(space.canTrash) ?? false)
        }
        .sorted(using: order)
    }

    var body: some View {
        let total = max(1, tree[space.focus].size)
        VStack(spacing: 8) {
            Table(rows, selection: selection, sortOrder: $order) {
                TableColumn("", value: \SpaceRow.id) { row in
                    Toggle(isOn: checked(row.id)) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .disabled(!row.canTrash)
                        .help(row.canTrash ? L("Scegli per il Cestino") : L("Questa voce non si sposta da qui"))
                        .accessibilityLabel(L("Scegli %@", row.name))
                }
                .width(22)
                TableColumn(L("Nome"), value: \SpaceRow.name) { row in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(row.kind.color.opacity(row.isSynthetic ? 0.45 : 1))
                            .frame(width: 9, height: 9)
                            .accessibilityHidden(true)
                        Image(systemName: row.isDirectory ? "folder" : (row.isSynthetic ? "square.grid.3x3" : "doc"))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(row.name).lineLimit(1).truncationMode(.middle)
                    }
                }
                .width(min: 160, ideal: 280)
                TableColumn(L("Dimensione"), value: \SpaceRow.size) { row in
                    HStack(spacing: 6) {
                        Text(Format.percent(Double(row.size) / Double(total)))
                            .foregroundStyle(.secondary)
                        Text(Format.diskBytes(row.size)).fontWeight(.semibold)
                    }
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 110, ideal: 130)
                TableColumn(L("Elementi"), value: \SpaceRow.items) { row in
                    Text(row.isDirectory || row.isSynthetic ? Format.number(Double(row.items), digits: 0) : "")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 60, ideal: 80)
                TableColumn(L("Modificato"), value: \SpaceRow.modified) { row in
                    Text(row.modified == .distantPast ? "" : row.modified.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 110)
                TableColumn(L("Tipo"), value: \SpaceRow.kindTitle) { row in
                    Text(row.kindTitle).foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 130)
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                menu(ids)
            } primaryAction: { ids in
                if let i = ids.first { space.open(i) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if !space.checked.isEmpty {
                checkedBar
            }
        }
    }

    /// Le voci spuntate, anche di altre cartelle: quante, quanto pesano, e il Cestino.
    private var checkedBar: some View {
        let bytes = space.checked.reduce(Int64(0)) { sum, i in
            tree.nodes.indices.contains(i) ? sum + tree[i].size : sum
        }
        return HStack(spacing: 10) {
            Text(L("%d scelti, %@", space.checked.count, Format.diskBytes(bytes)))
                .monospacedDigit()
            Spacer()
            Button(L("Togli le spunte")) { space.checked = [] }
                .buttonStyle(.borderless)
            Button(L("Sposta nel Cestino")) { space.trashChecked() }
                .glassButton()
        }
        .font(.callout)
        .controlSize(.small)
        .padding(.horizontal, 4)
    }

    @ViewBuilder private func menu(_ ids: Set<Int>) -> some View {
        if ids.count == 1, let i = ids.first, tree.nodes.indices.contains(i) {
            if tree[i].isDirectory, !tree[i].children.isEmpty {
                Button(L("Zoom avanti")) { space.open(i) }
            }
            if let path = tree.path(of: i) {
                Button(L("Mostra nel Finder")) { space.reveal(path) }
                Button(L("Copia il percorso")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
                if space.canTrash(path), let item = space.item(i) {
                    Divider()
                    Button(L("Sposta nel Cestino")) { space.trash([item]) }
                }
            }
        }
    }

    private var selection: Binding<Int?> {
        Binding(get: { space.selection }, set: { space.selection = $0 })
    }

    private func checked(_ id: Int) -> Binding<Bool> {
        Binding(get: { space.checked.contains(id) },
                set: { on in
                    if on { space.checked.insert(id) } else { space.checked.remove(id) }
                })
    }
}
