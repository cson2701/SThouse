//
//  InventoryItem.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import Foundation

struct InventoryItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var room: String
    var category: String
    var quantity: Int

    init(id: UUID = UUID(), name: String, room: String, category: String, quantity: Int) {
        self.id = id
        self.name = name
        self.room = room
        self.category = category
        self.quantity = quantity
    }
}
