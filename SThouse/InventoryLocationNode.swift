//
//  InventoryLocationNode.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import Foundation

struct InventoryLocationNode: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var sortOrder: Int
    var isDeleted: Bool
    var updatedAt: Date
    var serverUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        sortOrder: Int = 0,
        isDeleted: Bool = false,
        updatedAt: Date = .now,
        serverUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.serverUpdatedAt = serverUpdatedAt
    }
}
