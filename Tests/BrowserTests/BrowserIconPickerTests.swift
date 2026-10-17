import AppKit
import SwiftUI
import XCTest
@testable import Browser

@MainActor
final class BrowserIconPickerTests: XCTestCase {
    func testPopupPreservesTemplateImagesAndSelectionAcrossProfileChanges() throws {
        var selected = "personal"
        let coordinator = BrowserIconPicker<String>.Coordinator(selection: Binding(
            get: { selected }, set: { selected = $0 }))
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        let options: [BrowserIconPicker<String>.Option] = [
            .init(value: "personal", title: "Same name", icon: .globe),
            .init(value: "work", title: "Same name", icon: .briefcase)
        ]
        coordinator.update(button, options: options, selected: selected)
        XCTAssertEqual(button.numberOfItems, 2, "Profile identity must not depend on its display name")
        XCTAssertEqual(button.indexOfSelectedItem, 0)
        for item in button.itemArray {
            let image = try XCTUnwrap(item.image)
            XCTAssertTrue(image.isTemplate)
            XCTAssertTrue(image.name()?.hasPrefix("Lisiere.Hugeicons.") == true)
            XCTAssertTrue(try XCTUnwrap(item.onStateImage).isTemplate)
            if #available(macOS 27.0, *) {
                XCTAssertEqual(item.value(forKey: "preferredImageVisibility") as? Int, 1)
            }
        }
        button.selectItem(at: 1)
        coordinator.select(button)
        XCTAssertEqual(selected, "work")

        coordinator.update(button, options: [
            .init(value: "work", title: "Renamed", icon: .code)
        ], selected: selected)
        XCTAssertEqual(button.numberOfItems, 1)
        XCTAssertEqual(button.titleOfSelectedItem, "Renamed")
        XCTAssertEqual(button.selectedItem?.image?.name(), BrowserIcon.code.menuImage().name())
        XCTAssertEqual(selected, "work", "Rendering must not change the selected profile")
    }

    func testPopupUsesCurrentBindingAndIgnoresUnavailableSelection() {
        var previous = "a"
        var current = "a"
        let coordinator = BrowserIconPicker<String>.Coordinator(selection: Binding(
            get: { previous }, set: { previous = $0 }))
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        let options: [BrowserIconPicker<String>.Option] = [
            .init(value: "a", title: "Personal", icon: .globe),
            .init(value: "b", title: "Work", icon: .briefcase)
        ]
        coordinator.update(button, options: options, selected: "missing")
        coordinator.select(button)
        XCTAssertEqual(previous, "a")
        coordinator.selection = Binding(get: { current }, set: { current = $0 })
        button.selectItem(at: 1)
        button.isEnabled = false
        coordinator.select(button)
        XCTAssertEqual(current, "a")
        button.isEnabled = true
        coordinator.select(button)
        XCTAssertEqual(current, "b")
        XCTAssertEqual(previous, "a")
    }
}
