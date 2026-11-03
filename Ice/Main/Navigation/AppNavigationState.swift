//
//  AppNavigationState.swift
//  Ice
//

import Combine

/// The model for app-wide navigation.
@MainActor
final class AppNavigationState: ObservableObject {
    @Published var isAppFrontmost = false
    @Published var isSettingsPresented = false
    @Published var isIceBarPresented = false
    @Published var isSearchPresented = false
    @Published var isLayoutDragging = false
    @Published var settingsNavigationIdentifier: SettingsNavigationIdentifier = .general {
        didSet {
            guard oldValue != settingsNavigationIdentifier, !isTraversingHistory else { return }
            backHistory.append(oldValue)
            forwardHistory.removeAll()
        }
    }
    @Published private var backHistory = [SettingsNavigationIdentifier]()
    @Published private var forwardHistory = [SettingsNavigationIdentifier]()
    private var isTraversingHistory = false

    var canGoBack: Bool { !backHistory.isEmpty }
    var canGoForward: Bool { !forwardHistory.isEmpty }

    func goBack() {
        guard let previous = backHistory.popLast() else { return }
        isTraversingHistory = true
        forwardHistory.append(settingsNavigationIdentifier)
        settingsNavigationIdentifier = previous
        isTraversingHistory = false
    }

    func goForward() {
        guard let next = forwardHistory.popLast() else { return }
        isTraversingHistory = true
        backHistory.append(settingsNavigationIdentifier)
        settingsNavigationIdentifier = next
        isTraversingHistory = false
    }
}
