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

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.sortOrder = sortOrder
    }
}
