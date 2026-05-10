import Foundation

/// The number of Express Key slots per profile. Defined by spec constant EXPRESS_KEY_COUNT.
public let expressKeyCount = 6

/// A named collection of Express Key assignments.
///
/// Always contains exactly `expressKeyCount` (6) key slots in display order.
/// Slots with no assignment carry an empty label and keyCode/modifiers of 0.
public struct ExpressKeyProfile: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    /// Exactly 6 slots. Index = display position (0 = top).
    public var keys: [ExpressKey]

    public init(id: UUID = UUID(), name: String, keys: [ExpressKey]) {
        self.id = id
        self.name = name
        self.keys = keys
    }

    /// Returns a built-in default profile with 6 empty slots.
    public static func makeDefault() -> ExpressKeyProfile {
        let slots = (0 ..< expressKeyCount).map { i in
            ExpressKey(label: "", keyCode: 0, modifiers: 0, holdMode: .oneShot)
        }
        return ExpressKeyProfile(name: "Default", keys: slots)
    }
}
