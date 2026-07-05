//
//  AddItemViewModel.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class AddItemViewModel {
    var name = ""
    var selectedLocationID: UUID?
    var selectedCategoryID: String?
    var quantity = 1
    var lastEditedAt: Date?
    var lastEditedBy: String?

    private let editingItemID: UUID?

    init(item: InventoryItem? = nil, initialLocationID: UUID? = nil) {
        editingItemID = item?.id
        if let item {
            name = item.name
            selectedLocationID = item.locationID
            selectedCategoryID = item.category
            quantity = item.quantity
            lastEditedAt = item.updatedAt
            lastEditedBy = item.lastEditedBy
        } else {
            selectedLocationID = initialLocationID
        }
    }

    var canSave: Bool {
        !trimmedName.isEmpty && selectedLocationID != nil
    }

    var isEditing: Bool {
        editingItemID != nil
    }

    func makeItem(categoryID: String) -> InventoryItem {
        InventoryItem(
            id: editingItemID ?? UUID(),
            name: trimmedName,
            locationID: selectedLocationID,
            category: categoryID,
            quantity: quantity
        )
    }

    var itemID: UUID? {
        editingItemID
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
