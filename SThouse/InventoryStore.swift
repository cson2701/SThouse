//
//  InventoryStore.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import Foundation
import Observation
import SwiftUI
import FirebaseAuth
import Network

@MainActor
@Observable
final class InventoryStore {
    private static let sharedPersistenceNamespace = "shared-household"

    var items: [InventoryItem]
    var locations: [InventoryLocationNode]
    var syncIndicator: InventorySyncIndicator
    var lastSuccessfulSyncAt: Date?
    var pendingChangeCount: Int

    @ObservationIgnored private var pendingMutations: [InventoryPendingMutation]
    @ObservationIgnored private let persistence: InventoryLocalPersistence
    @ObservationIgnored private let remoteSync: InventoryRemoteSyncing
    @ObservationIgnored private let networkMonitor: NetworkMonitor
    @ObservationIgnored private var syncState: InventorySyncState
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    init(items: [InventoryItem]? = nil, locations: [InventoryLocationNode]? = nil) {
        let persistenceNamespace = Auth.auth().currentUser != nil ? Self.sharedPersistenceNamespace : "offline"
        let persistence = InventoryLocalPersistence(namespace: persistenceNamespace)
        self.persistence = persistence
        let networkMonitor = NetworkMonitor()
        self.networkMonitor = networkMonitor
        let remoteSync = FirebaseSyncClient()
        if remoteSync.isEnabled {
            self.remoteSync = remoteSync
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
            self.items = []
            self.locations = []
        }

        networkMonitor.onConnectivityChange = { [weak self] isConnected in
            Task { @MainActor [weak self] in
                self?.handleConnectivityChange(isConnected: isConnected)
            }
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
        let persistedItem = item.withUpdatedMetadata(editor: currentEditorIdentity())
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

        let updatedItem = item.withUpdatedMetadata(editor: currentEditorIdentity())
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
            for: item.markedDeleted(at: .now, editor: currentEditorIdentity()),
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
                    items[index].lastEditedBy = currentEditorIdentity()
                }
            }
        }

        for location in deletedLocations {
            enqueueLocationMutation(for: location, operation: .delete)
        }

        for item in items where item.locationID == nil {
            enqueueItemMutation(for: item.withUpdatedMetadata(editor: currentEditorIdentity()), operation: .upsert)
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

        guard networkMonitor.isConnected else {
            syncIndicator = .offline
            pendingChangeCount = pendingMutations.count
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
                } else if !networkMonitor.isConnected {
                    syncIndicator = .offline
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

    private func handleConnectivityChange(isConnected: Bool) {
        guard remoteSync.isEnabled else {
            syncIndicator = .disabled
            return
        }

        pendingChangeCount = pendingMutations.count

        if isConnected {
            guard syncIndicator == .offline else {
                return
            }

            if syncTask == nil {
                Task {
                    await syncNow()
                }
            }
        } else if syncTask == nil {
            syncIndicator = .offline
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

    private func localizedCategoryName(for categoryCode: String) -> String {
        InventoryCategory(rawValue: categoryCode)?.localizedTitle ?? categoryCode
    }

    private func currentEditorIdentity() -> String? {
        let user = Auth.auth().currentUser
        return user?.email ?? user?.uid
    }
}

private final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "SThouse.NetworkMonitor")
    var onConnectivityChange: ((Bool) -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onConnectivityChange?(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var isConnected: Bool {
        monitor.currentPath.status == .satisfied
    }
}

private extension InventoryItem {
    func withUpdatedMetadata(_ date: Date = .now, editor: String?) -> InventoryItem {
        var copy = self
        copy.updatedAt = date
        copy.lastEditedBy = editor
        copy.isDeleted = false
        return copy
    }

    func markedDeleted(at date: Date, editor: String?) -> InventoryItem {
        var copy = self
        copy.isDeleted = true
        copy.updatedAt = date
        copy.lastEditedBy = editor
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
