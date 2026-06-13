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

    var items: [InventoryItem]
    var activeSheet: Sheet?
    var pendingDeleteItem: InventoryItem?
    var isShowingDeleteConfirmation = false

    init(items: [InventoryItem]? = nil) {
        self.items = items ?? [
            InventoryItem(name: "Cordless Drill", room: "Garage", category: InventoryCategory.tools.rawValue, quantity: 1),
            InventoryItem(name: "Paper Towels", room: "Kitchen", category: InventoryCategory.supplies.rawValue, quantity: 6),
            InventoryItem(name: "Desk Lamp", room: "Office", category: InventoryCategory.electronics.rawValue, quantity: 1),
            InventoryItem(name: "Bed Sheets", room: "Bedroom", category: InventoryCategory.textiles.rawValue, quantity: 2)
        ]
    }

    var itemCount: Int {
        items.count
    }

    var totalQuantity: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    func addItem(_ item: InventoryItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            items.insert(item, at: 0)
        }
    }

    func updateItem(_ item: InventoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            items[index] = item
        }
    }

    func deleteItem(id: UUID) {
        withAnimation(.easeInOut(duration: 0.25)) {
            items.removeAll { $0.id == id }
        }
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

    func item(for id: UUID) -> InventoryItem? {
        items.first(where: { $0.id == id })
    }

    private func clearPendingDelete() {
        pendingDeleteItem = nil
        isShowingDeleteConfirmation = false
    }
}
