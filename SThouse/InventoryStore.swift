//
//  InventoryStore.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class InventoryStore {
    var items: [InventoryItem]
    var locations: [InventoryLocationNode]
    var syncIndicator: InventorySyncIndicator
    var lastSuccessfulSyncAt: Date?
    var pendingChangeCount: Int

    @ObservationIgnored private var pendingMutations: [InventoryPendingMutation]
    @ObservationIgnored private let persistence: InventoryLocalPersistence
    @ObservationIgnored private let remoteSync: InventoryRemoteSyncing
    @ObservationIgnored private var syncState: InventorySyncState
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    init(items: [InventoryItem]? = nil, locations: [InventoryLocationNode]? = nil) {
        let persistence = InventoryLocalPersistence()
        self.persistence = persistence
        if let configuration = FirebaseSyncConfiguration() {
            self.remoteSync = FirebaseSyncClient(configuration: configuration)
            self.syncIndicator = .idle
        } else {
            self.remoteSync = DisabledRemoteSyncClient()
            self.syncIndicator = .disabled
        }

        self.syncState = .empty
        self.lastSuccessfulSyncAt = nil
        self.pendingMutations = []
        self.pendingChangeCount = 0

        if let items, let locations {
            self.items = items
            self.locations = locations
        } else {
            let seed = Self.makeSeedData()
            self.items = seed.items
            self.locations = seed.locations
        }

        Task {
            await restorePersistedStateIfAvailable()
            await persistSnapshot()
            await syncNow()
        }
    }

    var itemCount: Int {
        items.count
    }

    var totalQuantity: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    var rootLocations: [InventoryLocationNode] {
        children(of: nil)
    }

    func addItem(_ item: InventoryItem) {
        let persistedItem = item.withUpdatedTimestamp()
        withAnimation(.easeInOut(duration: 0.25)) {
            items.insert(persistedItem, at: 0)
        }
        enqueueItemMutation(for: persistedItem, operation: .upsert)
        schedulePersistenceAndSync()
    }

    func updateItem(_ item: InventoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let updatedItem = item.withUpdatedTimestamp()
        withAnimation(.easeInOut(duration: 0.25)) {
            items[index] = updatedItem
        }
        enqueueItemMutation(for: updatedItem, operation: .upsert)
        schedulePersistenceAndSync()
    }

    func deleteItem(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            items.removeAll { $0.id == id }
        }

        enqueueItemMutation(
            for: item.markedDeleted(at: .now),
            operation: .delete
        )
        schedulePersistenceAndSync()
    }

    func addLocation(name: String, parentID: UUID?) -> InventoryLocationNode {
        let siblingCount = locations.filter { $0.parentID == parentID }.count
        let node = InventoryLocationNode(name: name, parentID: parentID, sortOrder: siblingCount)
        withAnimation(.easeInOut(duration: 0.25)) {
            locations.append(node)
        }
        enqueueLocationMutation(for: node.withUpdatedTimestamp(), operation: .upsert)
        schedulePersistenceAndSync()
        return node
    }

    func renameLocation(id: UUID, name: String) {
        guard let index = locations.firstIndex(where: { $0.id == id }) else {
            return
        }

        let updatedLocation = locations[index].renamed(name)
        withAnimation(.easeInOut(duration: 0.25)) {
            locations[index] = updatedLocation
        }
        enqueueLocationMutation(for: updatedLocation, operation: .upsert)
        schedulePersistenceAndSync()
    }

    func deleteLocationSubtree(id: UUID) {
        let idsToDelete = subtreeIDs(startingAt: id)
        let deletedLocations = locations
            .filter { idsToDelete.contains($0.id) }
            .map { $0.markedDeleted(at: .now) }

        withAnimation(.easeInOut(duration: 0.25)) {
            locations.removeAll { idsToDelete.contains($0.id) }
            for index in items.indices {
                if let locationID = items[index].locationID, idsToDelete.contains(locationID) {
                    items[index].locationID = nil
                    items[index].updatedAt = .now
                }
            }
        }

        for location in deletedLocations {
            enqueueLocationMutation(for: location, operation: .delete)
        }

        for item in items where item.locationID == nil {
            enqueueItemMutation(for: item.withUpdatedTimestamp(), operation: .upsert)
        }

        schedulePersistenceAndSync()
    }

    func location(id: UUID?) -> InventoryLocationNode? {
        guard let id else {
            return nil
        }

        return locations.first(where: { $0.id == id })
    }

    func children(of parentID: UUID?) -> [InventoryLocationNode] {
        locations
            .filter { $0.parentID == parentID }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    func hasChildren(_ id: UUID) -> Bool {
        locations.contains { $0.parentID == id }
    }

    func items(at locationID: UUID?) -> [InventoryItem] {
        items.filter { $0.locationID == locationID }
    }

    func items(matching query: String) -> [InventoryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        return items.filter { item in
            item.name.localizedCaseInsensitiveContains(trimmedQuery)
                || locationPathDescription(for: item.locationID).localizedCaseInsensitiveContains(trimmedQuery)
                || localizedCategoryName(for: item.category).localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    func directItemCount(at locationID: UUID?) -> Int {
        items(at: locationID).count
    }

    func totalItemCount(in locationID: UUID) -> Int {
        directItemCount(at: locationID) + children(of: locationID).reduce(0) { partialResult, child in
            partialResult + totalItemCount(in: child.id)
        }
    }

    func breadcrumb(for locationID: UUID?) -> [InventoryLocationNode] {
        guard let locationID else {
            return []
        }

        var path: [InventoryLocationNode] = []
        var currentID: UUID? = locationID

        while let current = location(id: currentID) {
            path.insert(current, at: 0)
            currentID = current.parentID
        }

        return path
    }

    func locationPathDescription(for locationID: UUID?) -> String {
        let path = breadcrumb(for: locationID)
        guard !path.isEmpty else {
            return String(localized: "inventory.location.unassigned")
        }

        return path.map(\.name).joined(separator: " > ")
    }

    func isLeafLocation(_ id: UUID) -> Bool {
        !hasChildren(id)
    }

    func syncNow() async {
        guard remoteSync.isEnabled else {
            syncIndicator = .disabled
            return
        }

        guard syncTask == nil else {
            return
        }

        syncIndicator = .syncing
        let snapshot = makeSnapshot()

        syncTask = Task {
            do {
                let result = try await remoteSync.sync(snapshot: snapshot)
                await MainActor.run {
                    applySyncResult(result)
                    syncTask = nil
                }
            } catch {
                await MainActor.run {
                    markSyncFailure(error)
                    syncTask = nil
                }
            }
        }

        await syncTask?.value
    }

    private func restorePersistedStateIfAvailable() async {
        do {
            if let snapshot = try persistence.load() {
                items = snapshot.items.filter { !$0.isDeleted }
                locations = snapshot.locations.filter { !$0.isDeleted }
                pendingMutations = snapshot.pendingMutations
                syncState = snapshot.syncState
                lastSuccessfulSyncAt = snapshot.syncState.lastSuccessfulSyncAt
                pendingChangeCount = snapshot.pendingMutations.count

                if !remoteSync.isEnabled {
                    syncIndicator = .disabled
                } else if let error = snapshot.syncState.lastErrorDescription {
                    syncIndicator = .failed(error)
                } else {
                    syncIndicator = .idle
                }
            }
        } catch {
            syncIndicator = .failed(error.localizedDescription)
        }
    }

    private func persistSnapshot() async {
        do {
            try persistence.save(makeSnapshot())
        } catch {
            syncIndicator = .failed(error.localizedDescription)
        }
    }

    private func schedulePersistenceAndSync() {
        pendingChangeCount = pendingMutations.count

        Task {
            await persistSnapshot()
            await syncNow()
        }
    }

    private func applySyncResult(_ result: InventorySyncResult) {
        withAnimation(.easeInOut(duration: 0.25)) {
            items = result.items
            locations = result.locations
        }

        let acknowledgedSet = Set(result.acknowledgedMutationIDs)
        pendingMutations.removeAll { acknowledgedSet.contains($0.id) }
        pendingChangeCount = pendingMutations.count
        syncState.lastSuccessfulSyncAt = result.syncedAt
        syncState.lastErrorDescription = nil
        lastSuccessfulSyncAt = result.syncedAt
        syncIndicator = .idle

        Task {
            await persistSnapshot()
        }
    }

    private func markSyncFailure(_ error: Error) {
        syncState.lastErrorDescription = error.localizedDescription
        syncIndicator = .failed(error.localizedDescription)
        pendingChangeCount = pendingMutations.count

        Task {
            await persistSnapshot()
        }
    }

    private func makeSnapshot() -> InventorySnapshot {
        InventorySnapshot(
            items: items,
            locations: locations,
            pendingMutations: pendingMutations,
            syncState: syncState
        )
    }

    private func enqueueItemMutation(for item: InventoryItem, operation: InventoryPendingMutation.Operation) {
        pendingMutations.removeAll {
            $0.entityType == .item && $0.entityID == item.id
        }
        pendingMutations.append(
            InventoryPendingMutation(
                entityType: .item,
                entityID: item.id,
                operation: operation,
                item: item
            )
        )
    }

    private func enqueueLocationMutation(for location: InventoryLocationNode, operation: InventoryPendingMutation.Operation) {
        pendingMutations.removeAll {
            $0.entityType == .location && $0.entityID == location.id
        }
        pendingMutations.append(
            InventoryPendingMutation(
                entityType: .location,
                entityID: location.id,
                operation: operation,
                location: location
            )
        )
    }

    private func subtreeIDs(startingAt id: UUID) -> Set<UUID> {
        var ids: Set<UUID> = [id]
        var pending: [UUID] = [id]

        while let currentID = pending.popLast() {
            let children = locations.filter { $0.parentID == currentID }
            for child in children {
                ids.insert(child.id)
                pending.append(child.id)
            }
        }

        return ids
    }

    private static func makeSeedData() -> (items: [InventoryItem], locations: [InventoryLocationNode]) {
        let bedroom = InventoryLocationNode(name: "Bedroom", parentID: nil, sortOrder: 0)
        let bedsideTable = InventoryLocationNode(name: "Bedside Table", parentID: bedroom.id, sortOrder: 0)
        let wardrobe = InventoryLocationNode(name: "Wardrobe", parentID: bedroom.id, sortOrder: 1)

        let livingRoom = InventoryLocationNode(name: "Living Room", parentID: nil, sortOrder: 1)
        let tvUnit = InventoryLocationNode(name: "TV Unit", parentID: livingRoom.id, sortOrder: 0)
        let leftDrawer = InventoryLocationNode(name: "Left Drawer", parentID: tvUnit.id, sortOrder: 0)
        let rightDrawer = InventoryLocationNode(name: "Right Drawer", parentID: tvUnit.id, sortOrder: 1)

        let kitchen = InventoryLocationNode(name: "Kitchen", parentID: nil, sortOrder: 2)
        let pantry = InventoryLocationNode(name: "Pantry", parentID: kitchen.id, sortOrder: 0)

        let garage = InventoryLocationNode(name: "Garage", parentID: nil, sortOrder: 3)
        let toolCabinet = InventoryLocationNode(name: "Tool Cabinet", parentID: garage.id, sortOrder: 0)

        let office = InventoryLocationNode(name: "Office", parentID: nil, sortOrder: 4)
        let desk = InventoryLocationNode(name: "Desk", parentID: office.id, sortOrder: 0)
        let deskDrawer = InventoryLocationNode(name: "Desk Drawer", parentID: desk.id, sortOrder: 0)

        let bathroom = InventoryLocationNode(name: "Bathroom", parentID: nil, sortOrder: 5)
        let cabinet = InventoryLocationNode(name: "Cabinet", parentID: bathroom.id, sortOrder: 0)

        let locations = [
            bedroom,
            bedsideTable,
            wardrobe,
            livingRoom,
            tvUnit,
            leftDrawer,
            rightDrawer,
            kitchen,
            pantry,
            garage,
            toolCabinet,
            office,
            desk,
            deskDrawer,
            bathroom,
            cabinet
        ]

        let items = [
            InventoryItem(name: "Cordless Drill", locationID: toolCabinet.id, category: InventoryCategory.tools.rawValue, quantity: 1),
            InventoryItem(name: "Paper Towels", locationID: pantry.id, category: InventoryCategory.supplies.rawValue, quantity: 6),
            InventoryItem(name: "Desk Lamp", locationID: deskDrawer.id, category: InventoryCategory.electronics.rawValue, quantity: 1),
            InventoryItem(name: "Bed Sheets", locationID: wardrobe.id, category: InventoryCategory.textiles.rawValue, quantity: 2)
        ]

        return (items, locations)
    }

    private func localizedCategoryName(for categoryCode: String) -> String {
        InventoryCategory(rawValue: categoryCode)?.localizedTitle ?? categoryCode
    }
}

private extension InventoryItem {
    func withUpdatedTimestamp(_ date: Date = .now) -> InventoryItem {
        var copy = self
        copy.updatedAt = date
        copy.isDeleted = false
        return copy
    }

    func markedDeleted(at date: Date) -> InventoryItem {
        var copy = self
        copy.isDeleted = true
        copy.updatedAt = date
        return copy
    }
}

private extension InventoryLocationNode {
    func withUpdatedTimestamp(_ date: Date = .now) -> InventoryLocationNode {
        var copy = self
        copy.updatedAt = date
        copy.isDeleted = false
        return copy
    }

    func renamed(_ name: String) -> InventoryLocationNode {
        var copy = self
        copy.name = name
        copy.updatedAt = .now
        return copy
    }

    func markedDeleted(at date: Date) -> InventoryLocationNode {
        var copy = self
        copy.isDeleted = true
        copy.updatedAt = date
        return copy
    }
}
