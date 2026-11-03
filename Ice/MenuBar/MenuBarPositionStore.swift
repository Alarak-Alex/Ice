import Foundation

/// Updates only the native menu bar order, preserving the rest of the preferences.
struct MenuBarPositionStore {
    enum Failure: LocalizedError {
        case invalidPositions, changed, saveFailed, notApplied

        var errorDescription: String? {
            switch self {
            case .invalidPositions: AppLanguage.localized("This item's position could not be identified safely.")
            case .changed: AppLanguage.localized("The menu bar layout changed. Refresh and try again.")
            case .saveFailed: AppLanguage.localized("macOS did not save the requested menu bar order.")
            case .notApplied: AppLanguage.localized("The system did not apply this order. Refresh and try again.")
            }
        }
    }

    let url: URL
    let backupURL: URL

    func positions() throws -> [String: Double] {
        let data = try Data(contentsOf: url)
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let positions = dictionary["TrailingItemPreferredPositions"] as? [String: Double],
              positions.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw Failure.invalidPositions
        }
        return positions
    }

    static func reordered(_ positions: [String: Double], keys: [String], moving source: String, before target: String, after: Bool = false) throws -> [String: Double] {
        guard Set(keys).count == keys.count,
              let sourceIndex = keys.firstIndex(of: source),
              keys.contains(target),
              keys.allSatisfy({ ($0.hasPrefix("status:") || $0.hasPrefix("module:")) && positions[$0] != nil }) else {
            throw Failure.invalidPositions
        }
        let originalSlots = keys.compactMap { positions[$0] }.map { $0.rounded() }
        guard originalSlots.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw Failure.invalidPositions
        }
        var order = keys
        order.remove(at: sourceIndex)
        guard let targetIndex = order.firstIndex(of: target) else { return positions }
        order.insert(source, at: targetIndex + (after ? 1 : 0))

        // MenuBarAgent legitimately stores tied slots. Resolve ties into a stable,
        // non-negative integer sequence before assigning the requested order.
        var slots = [Double]()
        for slot in originalSlots {
            let next = min(slot, (slots.last ?? .infinity) - (slots.isEmpty ? 0 : 1))
            slots.append(next)
        }
        if let minimum = slots.min(), minimum < 0 {
            slots = slots.map { $0 - minimum }
        }
        var result = positions
        for (key, slot) in zip(order, slots) where result[key] != slot {
            result[key] = slot
        }
        return result
    }

    func save(_ updated: [String: Double], replacing expected: [String: Double]) throws {
        guard try positions() == expected else { throw Failure.changed }
        let originalData = try Data(contentsOf: url)
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try originalData.write(to: backupURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        guard try positions() == expected else { throw Failure.changed }
        let domain = url.deletingPathExtension().path as CFString
        CFPreferencesSetValue("TrailingItemPreferredPositions" as CFString, updated as CFDictionary,
                              domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let synchronized = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let saved = try? positions()
        if !synchronized || saved != updated {
            CFPreferencesSetValue("TrailingItemPreferredPositions" as CFString, expected as CFDictionary,
                                  domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            throw Failure.saveFailed
        }
    }
}
