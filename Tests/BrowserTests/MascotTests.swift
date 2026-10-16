import AppKit
import XCTest
@testable import Browser

@MainActor
final class MascotTests: XCTestCase {
    func testChoicePersistsAndUnknownValuesFallBackToLutin() throws {
        let name = "MascotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertEqual(Mascot.current(in: defaults), .lutin)
        for mascot in Mascot.allCases {
            defaults.set(mascot.rawValue, forKey: Mascot.storageKey)
            let reopened = try XCTUnwrap(UserDefaults(suiteName: name))
            XCTAssertEqual(Mascot.current(in: reopened), mascot)
        }
        defaults.set("removed-mascot", forKey: Mascot.storageKey)
        XCTAssertEqual(Mascot.current(in: defaults), .lutin)
    }

    func testEveryChoiceHasBundledMascotAndDockImages() throws {
        for mascot in Mascot.allCases {
            for palette in MascotPalette.allCases {
                for name in [mascot.imageName(for: palette), mascot.iconName(for: palette)]
                    + ["body", "eyes", "pupils"].map({ "\(mascot.imageName(for: palette))-\($0)" }) {
                    let image = try XCTUnwrap(NSImage(named: name), "Missing bundled asset: \(name)")
                    XCTAssertTrue(image.isValid, name)
                    XCTAssertGreaterThan(image.size.width, 0, name)
                }
            }
        }
    }

    func testPalettePersistsWithoutChangingTheMascot() throws {
        let name = "MascotPaletteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(Mascot.eclaireur.rawValue, forKey: Mascot.storageKey)
        XCTAssertEqual(MascotPalette.current(in: defaults), .black)
        defaults.set(MascotPalette.white.rawValue, forKey: MascotPalette.storageKey)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertEqual(MascotPalette.current(in: reopened), .white)
        XCTAssertEqual(Mascot.current(in: reopened), .eclaireur)
        defaults.set("unknown-palette", forKey: MascotPalette.storageKey)
        XCTAssertEqual(MascotPalette.current(in: defaults), .black)
        XCTAssertEqual(Mascot.current(in: defaults), .eclaireur)
    }

    func testDefaultIconAndBloubLicenseAreBundled() throws {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "Lisiere")
        XCTAssertNotNil(Bundle.main.url(forResource: "Lisiere", withExtension: "icns"))
        let license = try XCTUnwrap(Bundle.main.url(forResource: "LICENSE-bloub", withExtension: "txt"))
        XCTAssertTrue(try String(contentsOf: license, encoding: .utf8).contains("Jérémy Perret"))
    }

    func testDockIconChangesAndDefaultRestoresTheBundleIcon() throws {
        defer { Mascot.defaultChoice.applyDockIcon(palette: .black) }
        Mascot.defaultChoice.applyDockIcon(palette: .black)
        let original = try XCTUnwrap(NSApp.applicationIconImage.tiffRepresentation)
        var rendered = Set<Data>()
        for mascot in Mascot.allCases {
            for palette in MascotPalette.allCases {
                mascot.applyDockIcon(palette: palette)
                let data = try XCTUnwrap(NSApp.applicationIconImage.tiffRepresentation)
                XCTAssertTrue(rendered.insert(data).inserted, "Duplicate icon: \(mascot), \(palette)")
            }
        }
        Mascot.defaultChoice.applyDockIcon(palette: .black)
        XCTAssertEqual(NSApp.applicationIconImage.tiffRepresentation, original)
    }
}
