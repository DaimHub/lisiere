import Foundation
import SwiftUI

/// Stable identifiers keep tab membership independent of a group's editable name and color.
struct TabGroup: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var color: TabGroupColor = .blue
    var isCollapsed = false
}

enum TabGroupColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case blue, purple, pink, red, orange, green, gray

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var tint: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .gray: .gray
        }
    }
}
