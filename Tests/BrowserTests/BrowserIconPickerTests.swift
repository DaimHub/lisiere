import AppKit
import SwiftUI
import XCTest
@testable import Browser

@MainActor
final class BrowserIconPickerTests: XCTestCase {
    func testUnchangedPopupKeepsItsSizeCacheButNewLabelsAndSelectionResize() {
        let coordinator = BrowserIconPicker<String>.Coordinator(selection: .constant("a"))
        let button = SizeTrackingPopup(frame: .zero, pullsDown: false)
        let options: [BrowserIconPicker<String>.Option] = [
            .init(value: "a", title: "A", icon: .globe),
            .init(value: "b", title: "A much longer profile label", icon: .briefcase)
        ]
        coordinator.update(button, options: options, selected: "a")
        let menu = button.menu
        button.sizeInvalidations = 0
        for _ in 0..<20 { coordinator.update(button, options: options, selected: "a") }
        XCTAssertEqual(button.sizeInvalidations, 0, "An unchanged picker must not trigger another native layout")
        XCTAssertTrue(button.menu === menu)
        coordinator.update(button, options: options, selected: "b")
        XCTAssertEqual(button.indexOfSelectedItem, 1)
        XCTAssertGreaterThan(button.sizeInvalidations, 0)
        let previousWidth = button.intrinsicContentSize.width
        coordinator.update(button, options: [
            .init(value: "b", title: "A renamed profile with an even longer displayed label", icon: .code)
        ], selected: "b")
        XCTAssertGreaterThan(button.intrinsicContentSize.width, previousWidth)
        XCTAssertEqual(button.titleOfSelectedItem, "A renamed profile with an even longer displayed label")
    }

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

@MainActor
private final class SizeTrackingPopup: NSPopUpButton {
    var sizeInvalidations = 0
    override func invalidateIntrinsicContentSize() {
        sizeInvalidations += 1
        super.invalidateIntrinsicContentSize()
    }
}
