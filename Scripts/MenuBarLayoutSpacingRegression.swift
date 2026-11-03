import Foundation

@main
struct MenuBarLayoutSpacingRegression {
    static func main() throws {
        let domain = "com.jordanbaird.Ice.SpacingRegression.\(UUID())" as CFString
        let keys = ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"]
        let hosts = [kCFPreferencesAnyHost, kCFPreferencesCurrentHost]
        defer {
            for host in hosts {
                for key in keys + ["unrelated"] {
                    CFPreferencesSetValue(key as CFString, nil, domain, kCFPreferencesCurrentUser, host)
                }
                CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, host)
            }
        }
        for host in hosts {
            for key in keys { CFPreferencesSetValue(key as CFString, 99 as CFNumber, domain, kCFPreferencesCurrentUser, host) }
            CFPreferencesSetValue("unrelated" as CFString, "keep" as CFString, domain, kCFPreferencesCurrentUser, host)
            CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, host)
        }
        for spacing in [MenuBarLayoutSpacing.small, .tiny, .none, .standard] {
            try MenuBarLayoutSpacingPreferences.save(spacing, applicationID: domain)
            for key in keys {
                let global = CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Int
                assert(global == spacing.value, "Both spacing preferences must match the selected preset")
                assert(CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) == nil,
                       "A host override must not mask the new global setting")
            }
            for host in hosts {
                assert(CFPreferencesCopyValue("unrelated" as CFString, domain, kCFPreferencesCurrentUser, host) as? String == "keep")
            }
        }
        assert(MenuBarLayoutSpacing.allCases.map(\.value) == [nil, 8, 2, 0])
        print("Spacing: all four presets, host override removal, default reset and unrelated preference preservation passed in an isolated domain")
    }
}
