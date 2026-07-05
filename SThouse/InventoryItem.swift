//
//  InventoryItem.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import Foundation

struct InventoryItem: Identifiable, Equatable, Codable {
    static let demoTag = "demo"

    let id: UUID
    var name: String
    var locationID: UUID?
    var category: String
    var quantity: Int
    var tag: String?
    var lastEditedBy: String?
    var isDeleted: Bool
    var updatedAt: Date
    var serverUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        locationID: UUID? = nil,
        category: String,
        quantity: Int,
        tag: String? = nil,
        lastEditedBy: String? = nil,
        isDeleted: Bool = false,
        updatedAt: Date = .now,
        serverUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.locationID = locationID
        self.category = category
        self.quantity = quantity
        self.tag = tag
        self.lastEditedBy = lastEditedBy
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.serverUpdatedAt = serverUpdatedAt
    }
}
