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
    var syncedAt: Date
}

struct InventorySnapshot: Codable {
    var items: [InventoryItem]
    var locations: [InventoryLocationNode]
    var pendingMutations: [InventoryPendingMutation]
    var syncState: InventorySyncState
    var version = 1
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
    }

    enum Operation: String, Codable {
        case upsert
        case delete
    }

    let id: UUID
    let entityType: EntityType
    let entityID: UUID
    let operation: Operation
    let item: InventoryItem?
    let location: InventoryLocationNode?
    let recordedAt: Date
    var retryCount: Int

    init(
        id: UUID = UUID(),
        entityType: EntityType,
        entityID: UUID,
        operation: Operation,
        item: InventoryItem? = nil,
        location: InventoryLocationNode? = nil,
        recordedAt: Date = .now,
        retryCount: Int = 0
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.operation = operation
        self.item = item
        self.location = location
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
