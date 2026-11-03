import Foundation

/// Edits existing per-application visibility approvals; system-module records are preserved.
struct MenuBarVisibilityStore {
    enum Failure: LocalizedError {
        case unidentified, changed, notApplied

        var errorDescription: String? {
            switch self {
            case .unidentified: AppLanguage.localized("This application's menu bar visibility could not be identified safely.")
            case .changed: AppLanguage.localized("Menu bar visibility changed in another application. Refresh and try again.")
            case .notApplied: AppLanguage.localized("macOS did not apply the requested visibility change.")
            }
        }
    }

    let url: URL
    let backupURL: URL
    var temporaryVisibilityJournalName = "MenuBarImageCapture.visibility.plist"

    var temporaryVisibilityJournalURL: URL {
        backupURL.deletingLastPathComponent().appendingPathComponent(temporaryVisibilityJournalName)
    }

    @discardableResult
    func beginTemporaryVisibility(for bundleID: String) throws -> Bool {
        guard let allowed = try approvals()[bundleID] else { throw Failure.unidentified }
        guard !allowed else { return false }
        var journal = try temporaryVisibilityJournal()
        journal[bundleID] = false
        try saveTemporaryVisibilityJournal(journal)
        do { try setAllowed(true, for: bundleID, replacing: false) }
        catch {
            if (try? approvals()[bundleID]) == false {
                journal.removeValue(forKey: bundleID)
                try saveTemporaryVisibilityJournal(journal)
            }
            throw error
        }
        return true
    }

    @MainActor
    func withTemporaryVisibility<T>(for bundleID: String, operation: () async throws -> T) async throws -> T {
        guard try beginTemporaryVisibility(for: bundleID) else { return try await operation() }
        let outcome: Result<T, Error>
        do { outcome = .success(try await operation()) }
        catch { outcome = .failure(error) }
        // A concurrent hide already restores the original state; never create a missing record.
        guard let current = try approvals()[bundleID] else { throw Failure.unidentified }
        if current { try setAllowed(false, for: bundleID, replacing: true) }
        var journal = try temporaryVisibilityJournal()
        journal.removeValue(forKey: bundleID)
        try saveTemporaryVisibilityJournal(journal)
        return try outcome.get()
    }

    /// The journal survives interruption between showing an item and restoring it.
    func restoreTemporaryVisibility() throws {
        var journal = try temporaryVisibilityJournal()
        for (bundleID, original) in journal {
            guard let current = try approvals()[bundleID] else { throw Failure.unidentified }
            if current != original { try setAllowed(original, for: bundleID, replacing: current) }
            journal.removeValue(forKey: bundleID)
            try saveTemporaryVisibilityJournal(journal)
        }
    }

    private func temporaryVisibilityJournal() throws -> [String: Bool] {
        guard FileManager.default.fileExists(atPath: temporaryVisibilityJournalURL.path) else { return [:] }
        return try PropertyListDecoder().decode([String: Bool].self, from: Data(contentsOf: temporaryVisibilityJournalURL))
    }

    private func saveTemporaryVisibilityJournal(_ journal: [String: Bool]) throws {
        if journal.isEmpty {
            if FileManager.default.fileExists(atPath: temporaryVisibilityJournalURL.path) {
                try FileManager.default.removeItem(at: temporaryVisibilityJournalURL)
            }
            return
        }
        try FileManager.default.createDirectory(at: temporaryVisibilityJournalURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try PropertyListEncoder().encode(journal).write(to: temporaryVisibilityJournalURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryVisibilityJournalURL.path)
    }

    func approvals() throws -> [String: Bool] {
        try Self.approvals(in: trackedData())
    }

    static func approvals(in data: Data) throws -> [String: Bool] {
        let records = try records(in: data)
        var result = [String: Bool]()
        var ambiguous = Set<String>()
        for record in records {
            guard let bundle = bundle(in: record), let allowed = record["isAllowed"] as? Bool else { continue }
            if result[bundle] != nil { ambiguous.insert(bundle) }
            result[bundle] = allowed
        }
        for bundle in ambiguous { result.removeValue(forKey: bundle) }
        return result
    }

    static func replacing(in data: Data, bundleID: String, allowed: Bool) throws -> Data {
        var records = try records(in: data)
        let matches = records.indices.filter { bundle(in: records[$0]) == bundleID && records[$0]["isAllowed"] is Bool }
        guard matches.count == 1, let index = matches.first else { throw Failure.unidentified }
        records[index]["isAllowed"] = allowed
        return try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0)
    }

    func setAllowed(_ allowed: Bool, for bundleID: String, replacing expected: Bool) throws {
        let original = try trackedData()
        guard try Self.approvals(in: original)[bundleID] == expected else { throw Failure.changed }
        let updated = try Self.replacing(in: original, bundleID: bundleID, allowed: allowed)
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Data(contentsOf: url).write(to: backupURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        guard try trackedData() == original else { throw Failure.changed }
        let domain = url.deletingPathExtension().path as CFString
        CFPreferencesSetValue("trackedApplications" as CFString, updated as CFData, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let synchronized = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard synchronized, (try? approvals()[bundleID]) == allowed else {
            CFPreferencesSetValue("trackedApplications" as CFString, original as CFData, domain,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            throw Failure.notApplied
        }
    }

    private func trackedData() throws -> Data {
        let root = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        guard let data = root?["trackedApplications"] as? Data else { throw Failure.unidentified }
        return data
    }

    private static func records(in data: Data) throws -> [[String: Any]] {
        guard let records = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw Failure.unidentified
        }
        return records
    }

    private static func bundle(in record: [String: Any]) -> String? {
        guard let location = record["location"] as? [String: Any],
              let bundle = location["bundle"] as? [String: Any] else { return nil }
        return bundle["_0"] as? String
    }
}
