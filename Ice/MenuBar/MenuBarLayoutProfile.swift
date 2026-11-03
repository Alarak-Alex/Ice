import Foundation
import SwiftUI

enum MenuBarLayoutSection: String, Codable, CaseIterable, Identifiable {
    case visible, hidden, alwaysHidden

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .visible: "Shown Items"
        case .hidden: "Hidden Items"
        case .alwaysHidden: "Always Hidden"
        }
    }

    var symbol: String {
        switch self {
        case .visible: "eyeglasses"
        case .hidden: "eyeglasses.slash"
        case .alwaysHidden: "eye.slash"
        }
    }
}

struct MenuBarLayoutProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sections = [String: MenuBarLayoutSection]()
    var positions = [String: Double]()
    /// The display this profile should be selected for automatically, if any.
    var automaticDisplayID: UInt32? = nil
    var spacers = [MenuBarLayoutSpacer]()
    var newItemPlacement = MenuBarNewItemPlacement()
}

struct MenuBarNewItemPlacement: Codable, Equatable {
    var section: MenuBarLayoutSection = .hidden
    var beforeID: String?
}

struct MenuBarLayoutSpacer: Codable, Identifiable, Equatable {
    var id = UUID()
    var section: MenuBarLayoutSection
    var beforeID: String?
    var width: Double = 16

    var validatedWidth: CGFloat {
        guard width.isFinite else { return 16 }
        return CGFloat(min(200, max(1, width.rounded())))
    }
}

extension MenuBarLayoutProfile {
    private enum CodingKeys: String, CodingKey { case id, name, sections, positions, automaticDisplayID, spacers, newItemPlacement }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sections = try container.decode([String: MenuBarLayoutSection].self, forKey: .sections)
        positions = try container.decode([String: Double].self, forKey: .positions)
        automaticDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .automaticDisplayID)
        spacers = try container.decodeIfPresent([MenuBarLayoutSpacer].self, forKey: .spacers) ?? []
        newItemPlacement = try container.decodeIfPresent(MenuBarNewItemPlacement.self, forKey: .newItemPlacement) ?? MenuBarNewItemPlacement()
    }
}
