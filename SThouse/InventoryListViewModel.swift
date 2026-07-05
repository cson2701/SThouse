//
//  InventoryListViewModel.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class InventoryListViewModel {
    enum Sheet: Identifiable {
        case add(UUID?)
        case edit(InventoryItem)

        var id: String {
            switch self {
            case .add(let locationID):
                if let locationID {
                    return "add-\(locationID.uuidString)"
                }
                return "add"
            case .edit(let item):
                return "edit-\(item.id.uuidString)"
            }
        }
    }

    let store: InventoryStore
    var activeSheet: Sheet?
    var pendingDeleteItem: InventoryItem?
    var isShowingDeleteConfirmation = false
    var searchQuery = ""

    init() {
        self.store = InventoryStore()
    }

    init(store: InventoryStore) {
        self.store = store
    }

    var items: [InventoryItem] {
        store.items
    }

    var filteredItems: [InventoryItem] {
        store.items(matching: searchQuery)
    }

    var isShowingSearchResults: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var itemCount: Int {
        store.itemCount
    }

    var totalQuantity: Int {
        store.totalQuantity
    }

    var syncIndicator: InventorySyncIndicator {
        store.syncIndicator
    }

    var pendingChangeCount: Int {
        store.pendingChangeCount
    }

    var lastSuccessfulSyncAt: Date? {
        store.lastSuccessfulSyncAt
    }

    var isAutoSyncEnabled: Bool {
        store.isAutoSyncEnabled
    }

    func addItem(_ item: InventoryItem) {
        store.addItem(item)
    }

    func updateItem(_ item: InventoryItem) {
        store.updateItem(item)
    }

    func deleteItem(id: UUID) {
        store.deleteItem(id: id)
    }

    func requestDelete(_ item: InventoryItem) {
        pendingDeleteItem = item
        isShowingDeleteConfirmation = true
    }

    func confirmDelete() {
        guard let pendingDeleteItem else {
            return
        }

        deleteItem(id: pendingDeleteItem.id)
        clearPendingDelete()
    }

    func cancelDelete() {
        clearPendingDelete()
    }

    func locationPathDescription(for locationID: UUID?) -> String {
        store.locationPathDescription(for: locationID)
    }

    func locationBreadcrumb(for locationID: UUID?) -> [InventoryLocationNode] {
        store.breadcrumb(for: locationID)
    }

    func location(id: UUID?) -> InventoryLocationNode? {
        store.location(id: id)
    }

    func children(of parentID: UUID?) -> [InventoryLocationNode] {
        store.children(of: parentID)
    }

    func hasChildren(_ id: UUID) -> Bool {
        store.hasChildren(id)
    }

    func addLocation(name: String, parentID: UUID?) -> InventoryLocationNode {
        store.addLocation(name: name, parentID: parentID)
    }

    var categories: [InventoryCategory] {
        store.sortedCategories
    }

    var defaultCategoryID: String {
        store.defaultCategoryID
    }

    func categoryName(for categoryID: String) -> String {
        store.categoryName(for: categoryID)
    }

    func category(id: String) -> InventoryCategory? {
        store.category(id: id)
    }

    @discardableResult
    func ensureCategory(named name: String) -> InventoryCategory {
        store.ensureCategory(named: name)
    }

    func renameCategory(id: String, name: String) {
        store.renameCategory(id: id, name: name)
    }

    func deleteCategory(id: String) {
        store.deleteCategory(id: id)
    }

    func renameLocation(id: UUID, name: String) {
        store.renameLocation(id: id, name: name)
    }

    func deleteLocationSubtree(id: UUID) {
        store.deleteLocationSubtree(id: id)
    }

    func syncNow() async {
        await store.syncNow()
    }

    func setAutoSyncEnabled(_ isEnabled: Bool) {
        store.setAutoSyncEnabled(isEnabled)
    }

    func addDemoData() {
        let pantry = addLocation(name: "Pantry", parentID: nil)
        let kitchen = addLocation(name: "Kitchen", parentID: nil)
        let livingRoom = addLocation(name: "Living Room", parentID: nil)
        let hallway = addLocation(name: "Hallway Closet", parentID: nil)
        let office = addLocation(name: "Office", parentID: nil)
        let laundry = addLocation(name: "Laundry", parentID: nil)

        let upperShelf = addLocation(name: "Upper Shelf", parentID: pantry.id)
        let lowerShelf = addLocation(name: "Lower Shelf", parentID: pantry.id)
        let fridge = addLocation(name: "Fridge", parentID: kitchen.id)
        let sinkCabinet = addLocation(name: "Sink Cabinet", parentID: kitchen.id)
        let mediaConsole = addLocation(name: "Media Console", parentID: livingRoom.id)
        let sofaStorage = addLocation(name: "Sofa Storage", parentID: livingRoom.id)
        let deskDrawer = addLocation(name: "Desk Drawer", parentID: office.id)
        let bookshelf = addLocation(name: "Bookshelf", parentID: office.id)
        let washerShelf = addLocation(name: "Washer Shelf", parentID: laundry.id)

        let kitchenCategory = ensureCategory(named: "Kitchen")
        let cleaningCategory = ensureCategory(named: "Cleaning")
        let electronicsCategory = ensureCategory(named: "Electronics")
        let officeCategory = ensureCategory(named: "Office")
        let textilesCategory = ensureCategory(named: "Textiles")
        let suppliesCategory = ensureCategory(named: "Supplies")
        let toolsCategory = ensureCategory(named: "Tools")
        let pantryCategory = ensureCategory(named: "Pantry")

        let demoItems: [(String, UUID?, String, Int)] = [
            ("Olive Oil", upperShelf.id, pantryCategory.id, 2),
            ("Pasta", upperShelf.id, pantryCategory.id, 6),
            ("Cereal", lowerShelf.id, pantryCategory.id, 3),
            ("Paper Towels", lowerShelf.id, suppliesCategory.id, 8),
            ("Soy Sauce", fridge.id, kitchenCategory.id, 1),
            ("Sparkling Water", fridge.id, kitchenCategory.id, 12),
            ("Dish Soap", sinkCabinet.id, cleaningCategory.id, 2),
            ("Sponges", sinkCabinet.id, cleaningCategory.id, 5),
            ("Remote Batteries", mediaConsole.id, electronicsCategory.id, 4),
            ("HDMI Cable", mediaConsole.id, electronicsCategory.id, 2),
            ("Throw Blanket", sofaStorage.id, textilesCategory.id, 2),
            ("Board Game Cards", sofaStorage.id, suppliesCategory.id, 1),
            ("Notebook", deskDrawer.id, officeCategory.id, 7),
            ("Pens", deskDrawer.id, officeCategory.id, 10),
            ("USB-C Charger", bookshelf.id, electronicsCategory.id, 3),
            ("Printer Paper", bookshelf.id, officeCategory.id, 2),
            ("Flashlight", hallway.id, toolsCategory.id, 2),
            ("Tape Measure", hallway.id, toolsCategory.id, 1),
            ("Laundry Pods", washerShelf.id, cleaningCategory.id, 24),
            ("Dryer Sheets", washerShelf.id, cleaningCategory.id, 80)
        ]

        for item in demoItems {
            addItem(
                InventoryItem(
                    name: item.0,
                    locationID: item.1,
                    category: item.2,
                    quantity: item.3,
                    tag: InventoryItem.demoTag
                )
            )
        }
    }

    func deleteDemoItems() {
        let demoItemIDs = items
            .filter { $0.tag == InventoryItem.demoTag }
            .map(\.id)

        for id in demoItemIDs {
            deleteItem(id: id)
        }
    }

    private func clearPendingDelete() {
        pendingDeleteItem = nil
        isShowingDeleteConfirmation = false
    }
}
