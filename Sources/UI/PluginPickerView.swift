import SwiftUI
import AppKit

struct PluginPickerView: View {
    @ObservedObject private var catalog = PluginCatalog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: String?
    @State private var showingErrors = false
    let onSelect: (PluginCatalogEntry) -> Void
    let manualSelection: () -> Void

    private var filtered: [PluginCatalogEntry] {
        catalog.entries.filter {
            query.isEmpty || "\($0.name) \($0.manufacturer) \($0.category)".localizedCaseInsensitiveContains(query)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var selected: PluginCatalogEntry? { filtered.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("VST3エフェクトを選択")).font(.title2.bold())
                Spacer()
                Button(L10n.text("閉じる")) { dismiss() }
            }
            TextField(L10n.text("名称・メーカー・カテゴリで検索"), text: $query)
                .textFieldStyle(.roundedBorder)
            PluginSelectionTable(entries: filtered, selection: $selection) { entry in onSelect(entry) }
            HStack {
                if catalog.scanning { ProgressView().controlSize(.small) }
                Text(catalog.progress).font(.caption).lineLimit(1)
                Spacer()
                if catalog.scanning {
                    Button(L10n.text("停止")) { catalog.cancel() }
                } else {
                    Button(L10n.text("再スキャン")) { catalog.scan(force: true) }
                }
                if !catalog.failures.isEmpty {
                    Button(L10n.text("読込エラー ({0})", [String(describing: catalog.failures.count)])) { showingErrors.toggle() }
                }
            }
            if showingErrors {
                ScrollView { Text(catalog.failures.joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(height: 100)
            }
            Text(L10n.text("システム／ユーザーのVST3フォルダを検索します。楽器は一覧から除外します。ステレオ処理への対応は挿入時に確認します。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("ファイルから選択…"), action: manualSelection)
                Spacer()
                Text(L10n.text("{0} エフェクト", [String(describing: filtered.count)])).foregroundStyle(.secondary)
                Button(L10n.text("挿入")) { if let selected { onSelect(selected) } }
                    .keyboardShortcut(.defaultAction).disabled(selected == nil)
            }
        }
        .padding(24).frame(width: 780, height: 540)
        .task { catalog.scan() }
    }
}

/// Native mouseDown selection avoids SwiftUI Table's pressure/context-menu gesture arbitration.
private struct PluginSelectionTable: NSViewRepresentable {
    let entries: [PluginCatalogEntry]
    @Binding var selection: String?
    let activate: (PluginCatalogEntry) -> Void
    final class ClickTable: NSTableView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        var rowSelected: ((Int) -> Void)?
        override func mouseDown(with event: NSEvent) {
            let row = row(at: convert(event.locationInWindow, from: nil))
            guard row >= 0 else { super.mouseDown(with: event); return }
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            rowSelected?(row)
            if event.clickCount == 2, let doubleAction { NSApp.sendAction(doubleAction, to: target, from: self) }
        }
        override func pressureChange(with event: NSEvent) {} // Firm clicks retain normal row selection.
    }
    final class Label: NSTextField {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var owner: PluginSelectionTable
        init(_ owner: PluginSelectionTable) { self.owner = owner }
        func numberOfRows(in tableView: NSTableView) -> Int { owner.entries.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let entry = owner.entries[row]
            let text = tableColumn?.identifier.rawValue == "name" ? entry.name : tableColumn?.identifier.rawValue == "manufacturer" ? entry.manufacturer : entry.category
            let field = Label(labelWithString: text)
            field.isEditable = false; field.isSelectable = false
            field.lineBreakMode = .byTruncatingTail; field.toolTip = text
            return field
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table = notification.object as? NSTableView else { return }
            owner.selection = owner.entries.indices.contains(table.selectedRow) ? owner.entries[table.selectedRow].id : nil
        }
        @objc func doubleClick(_ sender: NSTableView) {
            if owner.entries.indices.contains(sender.selectedRow) { owner.activate(owner.entries[sender.selectedRow]) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = ClickTable(frame: NSRect(x: 0, y: 0, width: 730, height: 310));
        table.rowSelected = { [weak coordinator = context.coordinator] row in
            guard let coordinator, coordinator.owner.entries.indices.contains(row) else { return }
            coordinator.owner.selection = coordinator.owner.entries[row].id
        }
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.allowsMultipleSelection = false; table.rowHeight = 25
        table.pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryClick)
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.doubleClick(_:))
        for (key, name, width) in [("name", L10n.text("名称"), 315.0), ("manufacturer", L10n.text("メーカー"), 180.0), ("category", L10n.text("カテゴリ"), 200.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key)); column.title = name; column.width = width
            table.addTableColumn(column)
        }
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let changed = context.coordinator.owner.entries != entries
        context.coordinator.owner = self
        if changed {
            table.reloadData()
            table.frame.size.height = max(scroll.contentSize.height, CGFloat(entries.count) * table.rowHeight)
        }
        if let selection, let index = entries.firstIndex(where: { $0.id == selection }), table.selectedRow != index {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }
}
