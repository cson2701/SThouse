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
        case add
        case edit(InventoryItem)

        var id: String {
            switch self {
            case .add:
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

    func renameLocation(id: UUID, name: String) {
        store.renameLocation(id: id, name: name)
    }

    func deleteLocationSubtree(id: UUID) {
        store.deleteLocationSubtree(id: id)
    }

    func syncNow() async {
        await store.syncNow()
    }

    private func clearPendingDelete() {
        pendingDeleteItem = nil
        isShowingDeleteConfirmation = false
    }
}
