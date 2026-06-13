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

enum InventoryRoom: String, CaseIterable, Identifiable {
    case unspecified
    case bathroom
    case bedroom
    case diningRoom
    case garage
    case hallway
    case kitchen
    case livingRoom
    case office

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .unspecified:
            String(localized: "inventory.room.default")
        case .bathroom:
            String(localized: "inventory.room.bathroom")
        case .bedroom:
            String(localized: "inventory.room.bedroom")
        case .diningRoom:
            String(localized: "inventory.room.diningRoom")
        case .garage:
            String(localized: "inventory.room.garage")
        case .hallway:
            String(localized: "inventory.room.hallway")
        case .kitchen:
            String(localized: "inventory.room.kitchen")
        case .livingRoom:
            String(localized: "inventory.room.livingRoom")
        case .office:
            String(localized: "inventory.room.office")
        }
    }
}

@MainActor
@Observable
final class AddItemViewModel {
    var name = ""
    var room: InventoryRoom = .unspecified
    var category: InventoryCategory = .unspecified
    var quantity = 1

    private let editingItemID: UUID?

    init(item: InventoryItem? = nil) {
        self.editingItemID = item?.id
        if let item {
            name = item.name
            room = InventoryRoom(rawValue: item.room) ?? .unspecified
            category = InventoryCategory(rawValue: item.category) ?? .unspecified
            quantity = item.quantity
        }
    }

    var canSave: Bool {
        !trimmedName.isEmpty
    }

    var isEditing: Bool {
        editingItemID != nil
    }

    func makeItem() -> InventoryItem {
        InventoryItem(
            id: editingItemID ?? UUID(),
            name: trimmedName,
            room: resolvedRoom.rawValue,
            category: resolvedCategory.rawValue,
            quantity: quantity
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var itemID: UUID? {
        editingItemID
    }

    private var resolvedRoom: InventoryRoom {
        switch room {
        case .unspecified:
            .hallway
        default:
            room
        }
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
