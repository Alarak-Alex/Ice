import Foundation

enum MenuBarItemIdentityResolver {
    static func resolve(bundleID: String, identifier: String, title: String, itemCount: Int, positions: [String: Double]) -> String? {
        let prefix = "status:\(bundleID)::"
        let aliases = [identifier, title].filter { !$0.isEmpty }.map(normalized)
        let candidates = positions.keys.filter { $0.hasPrefix(prefix) && positions[$0]?.isFinite == true }
        let matches = candidates.filter { aliases.contains(normalized(String($0.dropFirst(prefix.count)))) }
        if matches.count == 1 { return matches.first }
        if matches.isEmpty, itemCount == 1, candidates.count == 1 { return candidates.first }
        if matches.isEmpty, ["com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.menuextra.clock", "com.apple.MenuBarAgent"].contains(bundleID) {
            let modules = positions.keys.filter { $0.hasPrefix("module:") && positions[$0]?.isFinite == true }
            let moduleMatches = modules.filter { key in
                let name = normalized(String(key.dropFirst("module:".count)))
                return aliases.contains { $0 == name || $0 == moduleBase(name) }
            }
            if moduleMatches.count == 1 { return moduleMatches.first }
        }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "NSStatusItem ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func moduleBase(_ value: String) -> String {
        guard let separator = value.lastIndex(of: "-"),
              value[value.index(after: separator)...].allSatisfy(\.isNumber) else { return value }
        return String(value[..<separator])
    }
}
