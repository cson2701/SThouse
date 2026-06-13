//
//  InventoryItem.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import Foundation

struct InventoryItem: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var locationID: UUID?
    var category: String
    var quantity: Int

    init(
        id: UUID = UUID(),
        name: String,
        locationID: UUID? = nil,
        category: String,
        quantity: Int
    ) {
        self.id = id
        self.name = name
        self.locationID = locationID
        self.category = category
        self.quantity = quantity
    }
}
