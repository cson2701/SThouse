//
//  AddItemViewModel.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import Foundation
import Observation

enum InventoryCategory: String, CaseIterable, Identifiable {
    case unspecified
    case appliances
    case cleaning
    case electronics
    case furniture
    case kitchen
    case office
    case supplies
    case textiles
    case tools

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .unspecified:
            String(localized: "inventory.category.default")
        case .appliances:
            String(localized: "inventory.category.appliances")
        case .cleaning:
            String(localized: "inventory.category.cleaning")
        case .electronics:
            String(localized: "inventory.category.electronics")
        case .furniture:
            String(localized: "inventory.category.furniture")
        case .kitchen:
            String(localized: "inventory.category.kitchen")
        case .office:
            String(localized: "inventory.category.office")
        case .supplies:
            String(localized: "inventory.category.supplies")
        case .textiles:
            String(localized: "inventory.category.textiles")
        case .tools:
            String(localized: "inventory.category.tools")
        }
    }
}

@MainActor
@Observable
final class AddItemViewModel {
    var name = ""
    var selectedLocationID: UUID?
    var category: InventoryCategory = .unspecified
    var quantity = 1
    var lastEditedAt: Date?
    var lastEditedBy: String?

    private let editingItemID: UUID?

    init(item: InventoryItem? = nil, initialLocationID: UUID? = nil) {
        editingItemID = item?.id
        if let item {
            name = item.name
            selectedLocationID = item.locationID
            category = InventoryCategory(rawValue: item.category) ?? .unspecified
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

    func makeItem() -> InventoryItem {
        InventoryItem(
            id: editingItemID ?? UUID(),
            name: trimmedName,
            locationID: selectedLocationID,
            category: resolvedCategory.rawValue,
            quantity: quantity
        )
    }

    var itemID: UUID? {
        editingItemID
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedCategory: InventoryCategory {
        switch category {
        case .unspecified:
            .appliances
        default:
            category
        }
    }
}
