import Foundation
import Observation
import SwiftUI
import WebKit

enum ProfileAccent: String, CaseIterable, Codable, Identifiable {
    case sage
    case blue
    case violet
    case rose
    case amber
    case graphite

    var id: Self { self }

    var title: String {
        switch self {
        case .sage: "Sage"
        case .blue: "Ocean"
        case .violet: "Violet"
        case .rose: "Rose"
        case .amber: "Amber"
        case .graphite: "Graphite"
        }
    }

    var color: Color {
        switch self {
        case .sage: Color(red: 0.38, green: 0.49, blue: 0.54)
        case .blue: Color(red: 0.24, green: 0.48, blue: 0.76)
        case .violet: Color(red: 0.58, green: 0.42, blue: 0.76)
        case .rose: Color(red: 0.72, green: 0.35, blue: 0.48)
        case .amber: Color(red: 0.69, green: 0.47, blue: 0.19)
        case .graphite: Color(red: 0.46, green: 0.48, blue: 0.52)
        }
    }
}

