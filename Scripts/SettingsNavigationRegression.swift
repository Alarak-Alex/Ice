// Compile with SettingsView, SettingsSidebar, AppNavigationState, navigation
// identifiers, ReadWindow, RemoveSidebarToggle and AppLanguage.
import SwiftUI

struct GeneralSettingsPane: View { var body: some View { Text("General content") } }
struct MenuBarLayoutSettingsPane: View { var body: some View { Text("Layout content") } }
struct MenuBarAppearanceSettingsPane: View { var body: some View { Text("Style content") } }
struct HotkeysSettingsPane: View { var body: some View { Text("Hotkeys content") } }
struct AdvancedSettingsPane: View { var body: some View { Text("Advanced content") } }
struct AboutSettingsPane: View { var body: some View { Text("About content") } }

@main
struct SettingsNavigationRegression {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let state = AppNavigationState()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 750),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: SettingsView().environmentObject(state).readWindow { _ in })
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now.addingTimeInterval(0.1))

        func sidebar(in view: NSView) -> SettingsSidebarView? {
            if let sidebar = view as? SettingsSidebarView { return sidebar }
            return view.subviews.lazy.compactMap { sidebar(in: $0) }.first
        }
        let sidebar = sidebar(in: host)!
        let table = sidebar.tableView
        assert(table.numberOfRows == SettingsNavigationIdentifier.allCases.count)
        assert(table.acceptsFirstMouse(for: nil))
        assert(!NSApp.isActive && !window.isKeyWindow,
               "The regression must inspect an inactive settings window")
        for (row, identifier) in SettingsNavigationIdentifier.allCases.enumerated() {
            let rect = table.rect(ofRow: row)
            assert(rect.width >= 170 && rect.height == 32)
            for x in [rect.minX + 2, rect.midX, rect.maxX - 2] {
                let point = host.superview!.convert(NSPoint(x: x, y: rect.midY), from: table)
                let hit = host.hitTest(point)!
                assert(hit === table || hit.isDescendant(of: table),
                       "The search field and decorative labels must not intercept a sidebar click")
            }
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            assert(state.settingsNavigationIdentifier == identifier,
                   "Native sidebar action must select its corresponding pane")
            assert(window.firstResponder !== sidebar.searchField.currentEditor(),
                   "Navigation must end search-field editing")
        }
        state.goBack()
        assert(state.settingsNavigationIdentifier == .advanced)
        state.goForward()
        assert(state.settingsNavigationIdentifier == .about)

        sidebar.searchField.stringValue = "Menu Bar"
        sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        assert(table.numberOfRows == 2)
        assert(state.settingsNavigationIdentifier == .about,
               "Filtering must not silently navigate to a different pane")
        sidebar.searchField.stringValue = "no-matching-settings"
        sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        assert(table.numberOfRows == 0 && table.selectedRow == -1)
        sidebar.searchField.stringValue = ""
        sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        assert(table.numberOfRows == 6 && table.selectedRow == 5)
        print("Settings sidebar: six native rows, isolated search hit area, first-mouse acceptance, navigation, history and filtering passed")
    }
}
