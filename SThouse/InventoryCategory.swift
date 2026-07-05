//
//  InventoryCategory.swift
//  SThouse
//
//  Created by Codex on 5/7/2026.
//

import Foundation

struct InventoryCategory: Identifiable, Equatable, Codable {
    static let uncategorizedID = "uncategorized"

    let id: String
    var name: String
    var sortOrder: Int
    var isDeleted: Bool
    var updatedAt: Date
    var serverUpdatedAt: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        sortOrder: Int,
        isDeleted: Bool = false,
        updatedAt: Date = .now,
        serverUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.serverUpdatedAt = serverUpdatedAt
    }

    func renamed(_ newName: String) -> InventoryCategory {
        var copy = self
        copy.name = newName
        copy.updatedAt = .now
        return copy
    }

    func markedDeleted(at date: Date = .now) -> InventoryCategory {
        var copy = self
        copy.isDeleted = true
        copy.updatedAt = date
        return copy
    }

    func withUpdatedTimestamp(_ date: Date = .now) -> InventoryCategory {
        var copy = self
        copy.updatedAt = date
        return copy
    }
}

extension InventoryCategory {
    static func defaultCategories() -> [InventoryCategory] {
        [
            InventoryCategory(
                id: uncategorizedID,
                name: String(localized: "inventory.category.uncategorized"),
                sortOrder: 0
            )
        ]
    }
}
