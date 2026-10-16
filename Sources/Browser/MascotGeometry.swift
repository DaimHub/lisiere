import SwiftUI

extension Mascot {
    /// Centers measured from the source artwork; both palettes use the same geometry.
    var eyeGeometry: (centerOffset: CGSize, anchor: UnitPoint) {
        switch self {
        case .eclaireur: (CGSize(width: -3.97148, height: 0.57422), UnitPoint(x: 0.69139, y: 0.47089))
        case .flamme: (CGSize(width: -4.30605, height: 0.28652), UnitPoint(x: 0.53828, y: 0.66985))
        case .goutte: (CGSize(width: 3.77930, height: -3.97148), UnitPoint(x: 0.46292, y: 0.55063))
        case .lapin: (CGSize(width: 3.87539, height: -0.52676), UnitPoint(x: 0.49960, y: 0.66667))
        case .lutin: (CGSize(width: 5.35898, height: -0.19102), UnitPoint(x: 0.49163, y: 0.50997))
        case .nuage: (CGSize(width: 3.68379, height: -1.00488), UnitPoint(x: 0.45056, y: 0.53628))
        case .ourson: (CGSize(width: -2.63145, height: 3.92344), UnitPoint(x: 0.51874, y: 0.41587))
        case .pollen: (CGSize(width: -3.63633, height: 0.04746), UnitPoint(x: 0.50718, y: 0.50040))
        case .veilleur: (CGSize(width: -2.58398, height: 3.44531), UnitPoint(x: 0.51595, y: 0.36683))
        }
    }
}
