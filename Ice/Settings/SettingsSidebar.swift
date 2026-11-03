//
//  SettingsSidebar.swift
//  Ice
//

import SwiftUI

struct SettingsSidebar: NSViewRepresentable {
    let selection: SettingsNavigationIdentifier
    let language: String
    let onSelect: (SettingsNavigationIdentifier) -> Void

    func makeNSView(context: Context) -> SettingsSidebarView {
        SettingsSidebarView()
    }

    func updateNSView(_ view: SettingsSidebarView, context: Context) {
        view.onSelect = onSelect
        view.update(selection: selection, language: language)
    }
}

final class SettingsSidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private final class NavigationTable: NSTableView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private final class NavigationCell: NSTableCellView {
        let badge = NSView()
        let glyph = NSImageView()
        let label = NSTextField(labelWithString: "")

        override init(frame: NSRect) {
            super.init(frame: frame)
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.systemBlue.cgColor
            badge.layer?.cornerRadius = 5
            glyph.contentTintColor = .white
            glyph.imageScaling = .scaleProportionallyDown
            glyph.symbolConfiguration = .init(pointSize: 12, weight: .medium)
            badge.addSubview(glyph)
            addSubview(badge)
            label.font = .systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
            textField = label
        }

        required init?(coder: NSCoder) { nil }

        override var backgroundStyle: NSView.BackgroundStyle {
            didSet {
                label.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .labelColor
            }
        }

        override func layout() {
            super.layout()
            badge.frame = NSRect(x: 6, y: (bounds.height - 20) / 2, width: 20, height: 20)
            glyph.frame = badge.bounds.insetBy(dx: 3, dy: 3)
            label.frame = NSRect(x: 34, y: (bounds.height - 18) / 2, width: max(0, bounds.width - 40), height: 18)
        }
    }

    let searchField = NSSearchField()
    let tableView: NSTableView = NavigationTable()
    private var identifiers = Array(SettingsNavigationIdentifier.allCases)
    private var selection = SettingsNavigationIdentifier.general
    private var language = ""
    private var isUpdatingSelection = false
    var onSelect: (SettingsNavigationIdentifier) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)

        searchField.font = .systemFont(ofSize: 13)
        searchField.focusRingType = .none
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
        searchField.delegate = self
        searchField.setAccessibilityIdentifier("settings-sidebar-search")
        searchField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settings-navigation"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = 32
        tableView.intercellSpacing = .zero
        tableView.autoresizingMask = [.width]
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityIdentifier("settings-sidebar-navigation")
        tableView.setAccessibilityLabel(AppLanguage.localized("Settings"))

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(selection: SettingsNavigationIdentifier, language: String) {
        self.selection = selection
        if self.language != language {
            self.language = language
            searchField.placeholderString = AppLanguage.localized("Search")
            reloadNavigation()
        } else {
            updateSelection()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        reloadNavigation()
    }

    private func reloadNavigation() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        identifiers = SettingsNavigationIdentifier.allCases.filter {
            query.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(query)
                || title(for: $0).localizedCaseInsensitiveContains(query)
        }
        isUpdatingSelection = true
        tableView.reloadData()
        isUpdatingSelection = false
        updateSelection()
    }

    private func updateSelection() {
        isUpdatingSelection = true
        if let row = identifiers.firstIndex(of: selection) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        isUpdatingSelection = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { identifiers.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.setAccessibilityIdentifier("settings-navigation-\(identifiers[row].rawValue)")
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = identifiers[row]
        let cell = NavigationCell()
        cell.label.stringValue = title(for: identifier)
        cell.glyph.image = NSImage(systemSymbolName: symbol(for: identifier), accessibilityDescription: nil)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection, identifiers.indices.contains(tableView.selectedRow) else { return }
        selection = identifiers[tableView.selectedRow]
        window?.makeFirstResponder(tableView)
        onSelect(selection)
    }

    private func title(for identifier: SettingsNavigationIdentifier) -> String {
        AppLanguage.localized(String.LocalizationValue(identifier.titleKey))
    }

    private func symbol(for identifier: SettingsNavigationIdentifier) -> String {
        switch identifier {
        case .general: "gearshape"
        case .menuBarLayout: "menubar.rectangle"
        case .menuBarAppearance: "paintbrush.fill"
        case .hotkeys: "keyboard"
        case .advanced: "gearshape.2"
        case .about: "info"
        }
    }
}
