//
//  InventorySyncModels.swift
//  SThouse
//
//  Created by Codex on 27/6/2026.
//

import Foundation

struct InventoryRemoteSnapshot {
    var items: [InventoryItem]
    var locations: [InventoryLocationNode]
    var categories: [InventoryCategory]
    var syncedAt: Date
}

struct InventorySnapshot: Codable {
    var items: [InventoryItem]
    var locations: [InventoryLocationNode]
    var categories: [InventoryCategory]
    var pendingMutations: [InventoryPendingMutation]
    var syncState: InventorySyncState
    var version = 2

    init(
        items: [InventoryItem],
        locations: [InventoryLocationNode],
        categories: [InventoryCategory],
        pendingMutations: [InventoryPendingMutation],
        syncState: InventorySyncState,
        version: Int = 2
    ) {
        self.items = items
        self.locations = locations
        self.categories = categories
        self.pendingMutations = pendingMutations
        self.syncState = syncState
        self.version = version
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case locations
        case categories
        case pendingMutations
        case syncState
        case version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([InventoryItem].self, forKey: .items)
        locations = try container.decode([InventoryLocationNode].self, forKey: .locations)
        categories = try container.decodeIfPresent([InventoryCategory].self, forKey: .categories) ?? InventoryCategory.defaultCategories()
        pendingMutations = try container.decode([InventoryPendingMutation].self, forKey: .pendingMutations)
        syncState = try container.decode(InventorySyncState.self, forKey: .syncState)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}

struct InventorySyncState: Codable, Equatable {
    var lastSuccessfulSyncAt: Date?
    var lastErrorDescription: String?

    static let empty = InventorySyncState(lastSuccessfulSyncAt: nil, lastErrorDescription: nil)
}

struct InventoryPendingMutation: Identifiable, Codable, Equatable {
    enum EntityType: String, Codable {
        case item
        case location
        case category
    }

    enum Operation: String, Codable {
        case upsert
        case delete
    }

    let id: UUID
    let entityType: EntityType
    let entityID: String
    let operation: Operation
    let item: InventoryItem?
    let location: InventoryLocationNode?
    let category: InventoryCategory?
    let recordedAt: Date
    var retryCount: Int

    init(
        id: UUID = UUID(),
        entityType: EntityType,
        entityID: String,
        operation: Operation,
        item: InventoryItem? = nil,
        location: InventoryLocationNode? = nil,
        category: InventoryCategory? = nil,
        recordedAt: Date = .now,
        retryCount: Int = 0
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.operation = operation
        self.item = item
        self.location = location
        self.category = category
        self.recordedAt = recordedAt
        self.retryCount = retryCount
    }
}

enum InventorySyncIndicator: Equatable {
    case disabled
    case idle
    case offline
    case syncing
    case failed(String)

    var title: String {
        switch self {
        case .disabled:
            return String(localized: "inventory.sync.status.offlineOnly")
        case .idle:
            return String(localized: "inventory.sync.status.synced")
        case .offline:
            return String(localized: "inventory.sync.status.offline")
        case .syncing:
            return String(localized: "inventory.sync.status.syncing")
        case .failed:
            return String(localized: "inventory.sync.status.failed")
        }
    }

    var systemImageName: String {
        switch self {
        case .disabled:
            return "wifi.slash"
        case .idle:
            return "checkmark.icloud"
        case .offline:
            return "wifi.exclamationmark"
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .failed:
            return "exclamationmark.icloud"
        }
    }
}

struct InventorySyncResult {
    var items: [InventoryItem]
    var locations: [InventoryLocationNode]
    var categories: [InventoryCategory]
    var acknowledgedMutationIDs: [UUID]
    var syncedAt: Date
}

protocol InventoryRemoteSyncing: AnyObject {
    var isEnabled: Bool { get }
    func sync(snapshot: InventorySnapshot) async throws -> InventorySyncResult
    func startListening(
        onUpdate: @escaping @Sendable (InventoryRemoteSnapshot) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    )
    func stopListening()
}
