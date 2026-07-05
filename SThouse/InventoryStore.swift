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
    private static let autoSyncPreferenceKeyPrefix = "inventory.autoSync"

    var items: [InventoryItem]
    var locations: [InventoryLocationNode]
    var categories: [InventoryCategory]
    var isAutoSyncEnabled: Bool
    var syncIndicator: InventorySyncIndicator
    var lastSuccessfulSyncAt: Date?
    var pendingChangeCount: Int

    @ObservationIgnored private var pendingMutations: [InventoryPendingMutation]
    @ObservationIgnored private let persistence: InventoryLocalPersistence
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let autoSyncPreferenceKey: String
    @ObservationIgnored private let remoteSync: InventoryRemoteSyncing
    @ObservationIgnored private let networkMonitor: NetworkMonitor
    @ObservationIgnored private var syncState: InventorySyncState
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    init(
        items: [InventoryItem]? = nil,
        locations: [InventoryLocationNode]? = nil,
        categories: [InventoryCategory]? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        let persistenceNamespace = Auth.auth().currentUser != nil ? Self.sharedPersistenceNamespace : "offline"
        let persistence = InventoryLocalPersistence(namespace: persistenceNamespace)
        self.persistence = persistence
        self.userDefaults = userDefaults
        self.autoSyncPreferenceKey = "\(Self.autoSyncPreferenceKeyPrefix).\(persistenceNamespace)"
        let networkMonitor = NetworkMonitor()
        self.networkMonitor = networkMonitor
        let remoteSync = FirebaseSyncClient()
        self.isAutoSyncEnabled = userDefaults.object(forKey: "\(Self.autoSyncPreferenceKeyPrefix).\(persistenceNamespace)") as? Bool ?? true
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
            self.categories = Self.normalizedCategories(categories ?? InventoryCategory.defaultCategories())
        } else {
            self.items = []
            self.locations = []
            self.categories = InventoryCategory.defaultCategories()
        }

        networkMonitor.onConnectivityChange = { [weak self] isConnected in
            Task { @MainActor [weak self] in
                self?.handleConnectivityChange(isConnected: isConnected)
            }
        }

        startRemoteListenerIfNeeded()

        Task {
            await restorePersistedStateIfAvailable()
            await persistSnapshot()
            if isAutoSyncEnabled {
                await syncNow()
            }
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

    var sortedCategories: [InventoryCategory] {
        categories
            .filter { !$0.isDeleted }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    var defaultCategoryID: String {
        categories.contains(where: { $0.id == InventoryCategory.uncategorizedID && !$0.isDeleted })
            ? InventoryCategory.uncategorizedID
            : sortedCategories.first?.id ?? InventoryCategory.uncategorizedID
    }

    func addItem(_ item: InventoryItem) {
        let persistedItem = item
            .assigningCategory(resolveCategoryID(for: item.category, fallbackName: nil))
            .withUpdatedMetadata(editor: currentEditorIdentity())
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

        let updatedItem = item
            .assigningCategory(resolveCategoryID(for: item.category, fallbackName: nil))
            .withUpdatedMetadata(editor: currentEditorIdentity())
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

    @discardableResult
    func ensureCategory(named name: String) -> InventoryCategory {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = sortedCategories.first(where: { $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return existing
        }

        let category = InventoryCategory(name: trimmedName, sortOrder: sortedCategories.count)
        withAnimation(.easeInOut(duration: 0.25)) {
            categories.append(category)
        }
        enqueueCategoryMutation(for: category.withUpdatedTimestamp(), operation: .upsert)
        schedulePersistenceAndSync()
        return category
    }

    func renameCategory(id: String, name: String) {
        guard id != defaultCategoryID else {
            return
        }

        guard let index = categories.firstIndex(where: { $0.id == id }) else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let updatedCategory = categories[index].renamed(trimmedName)
        withAnimation(.easeInOut(duration: 0.25)) {
            categories[index] = updatedCategory
        }
        enqueueCategoryMutation(for: updatedCategory, operation: .upsert)
        schedulePersistenceAndSync()
    }

    func deleteCategory(id: String) {
        guard id != defaultCategoryID, let category = categories.first(where: { $0.id == id }) else {
            return
        }

        let fallbackCategoryID = defaultCategoryID
        let deletedCategory = category.markedDeleted(at: .now)
        let editor = currentEditorIdentity()
        var reassignedItemIDs: [UUID] = []

        withAnimation(.easeInOut(duration: 0.25)) {
            categories.removeAll { $0.id == id }
            for index in items.indices where items[index].category == id {
                items[index].category = fallbackCategoryID
                items[index].updatedAt = .now
                items[index].lastEditedBy = editor
                reassignedItemIDs.append(items[index].id)
            }
        }

        enqueueCategoryMutation(for: deletedCategory, operation: .delete)

        for item in items where reassignedItemIDs.contains(item.id) {
            enqueueItemMutation(for: item.withUpdatedMetadata(editor: editor), operation: .upsert)
        }

        schedulePersistenceAndSync()
    }

    func category(id: String) -> InventoryCategory? {
        categories.first(where: { $0.id == id && !$0.isDeleted })
    }

    func categoryName(for categoryID: String) -> String {
        category(id: categoryID)?.name ?? categoryID
    }

    func setAutoSyncEnabled(_ isEnabled: Bool) {
        guard isAutoSyncEnabled != isEnabled else {
            return
        }

        isAutoSyncEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: autoSyncPreferenceKey)

        if isEnabled {
            startRemoteListenerIfNeeded()
            Task {
                await syncNow()
            }
        } else {
            remoteSync.stopListening()
            if remoteSync.isEnabled {
                syncIndicator = networkMonitor.isConnected ? .idle : .offline
            } else {
                syncIndicator = .disabled
            }
        }
    }

    func resolveCategoryID(for rawValue: String?, fallbackName: String?) -> String {
        let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedValue.isEmpty, category(id: trimmedValue) != nil {
            return trimmedValue
        }

        if !trimmedValue.isEmpty,
           let match = sortedCategories.first(where: { $0.name.compare(trimmedValue, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return match.id
        }

        if !trimmedValue.isEmpty {
            let legacyDefaults = Self.legacyBuiltInCategoryLookup()
            if let legacyName = legacyDefaults[trimmedValue] {
                return ensureCategory(named: legacyName).id
            }

            return ensureCategory(named: trimmedValue).id
        }

        if let fallbackName {
            return ensureCategory(named: fallbackName).id
        }

        return defaultCategoryID
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

        return items.filter { matchesSearch($0, query: trimmedQuery) }
    }

    func matchesSearch(_ item: InventoryItem, query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return true
        }

        return item.name.localizedCaseInsensitiveContains(trimmedQuery)
            || locationPathDescription(for: item.locationID).localizedCaseInsensitiveContains(trimmedQuery)
            || categoryName(for: item.category).localizedCaseInsensitiveContains(trimmedQuery)
    }

    func matchesSearch(_ location: InventoryLocationNode, query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return true
        }

        return location.name.localizedCaseInsensitiveContains(trimmedQuery)
            || locationPathDescription(for: location.id).localizedCaseInsensitiveContains(trimmedQuery)
    }

    func hasTreeMatches(for query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return !rootLocations.isEmpty || !items.isEmpty
        }

        if items(at: nil).contains(where: { matchesSearch($0, query: trimmedQuery) }) {
            return true
        }

        return rootLocations.contains { locationHasTreeMatch($0, query: trimmedQuery) }
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
                items = snapshot.items.filter { !$0.isDeleted }.map(normalizedItem(_:))
                locations = snapshot.locations.filter { !$0.isDeleted }
                categories = Self.normalizedCategories(snapshot.categories)
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
            if isAutoSyncEnabled {
                await syncNow()
            }
        }
    }

    private func startRemoteListenerIfNeeded() {
        guard remoteSync.isEnabled, isAutoSyncEnabled else {
            return
        }

        remoteSync.startListening(
            onUpdate: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.applyRemoteSnapshot(snapshot)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleRemoteListenerError(error)
                }
            }
        )
    }

    private func applyRemoteSnapshot(_ snapshot: InventoryRemoteSnapshot) {
        let merged = mergedRemoteSnapshot(snapshot)

        withAnimation(.easeInOut(duration: 0.25)) {
            items = merged.items.map(normalizedItem(_:))
            locations = merged.locations
            categories = Self.normalizedCategories(merged.categories)
        }

        syncState.lastSuccessfulSyncAt = snapshot.syncedAt
        syncState.lastErrorDescription = nil
        lastSuccessfulSyncAt = snapshot.syncedAt

        if syncTask == nil {
            syncIndicator = networkMonitor.isConnected ? .idle : .offline
        }

        Task {
            await persistSnapshot()
        }
    }

    private func mergedRemoteSnapshot(_ snapshot: InventoryRemoteSnapshot) -> InventoryRemoteSnapshot {
        var itemMap = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        var locationMap = Dictionary(uniqueKeysWithValues: snapshot.locations.map { ($0.id, $0) })
        var categoryMap = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) })

        for mutation in pendingMutations.sorted(by: { $0.recordedAt < $1.recordedAt }) {
            switch mutation.entityType {
            case .item:
                switch mutation.operation {
                case .upsert:
                    if let item = mutation.item {
                        itemMap[item.id] = item
                    }
                case .delete:
                    if let itemID = UUID(uuidString: mutation.entityID) {
                        itemMap.removeValue(forKey: itemID)
                    }
                }
            case .location:
                switch mutation.operation {
                case .upsert:
                    if let location = mutation.location {
                        locationMap[location.id] = location
                    }
                case .delete:
                    if let locationID = UUID(uuidString: mutation.entityID) {
                        locationMap.removeValue(forKey: locationID)
                    }
                }
            case .category:
                switch mutation.operation {
                case .upsert:
                    if let category = mutation.category {
                        categoryMap[category.id] = category
                    }
                case .delete:
                    if let deletedCategory = mutation.category {
                        categoryMap[deletedCategory.id] = deletedCategory
                    }
                }
            }
        }

        return InventoryRemoteSnapshot(
            items: Array(itemMap.values).filter { !$0.isDeleted },
            locations: Array(locationMap.values).filter { !$0.isDeleted },
            categories: Self.normalizedCategories(Array(categoryMap.values)),
            syncedAt: snapshot.syncedAt
        )
    }

    private func handleRemoteListenerError(_ error: Error) {
        guard syncTask == nil, networkMonitor.isConnected else {
            return
        }

        syncState.lastErrorDescription = error.localizedDescription
        syncIndicator = .failed(error.localizedDescription)

        Task {
            await persistSnapshot()
        }
    }

    private func applySyncResult(_ result: InventorySyncResult) {
        withAnimation(.easeInOut(duration: 0.25)) {
            items = result.items.map(normalizedItem(_:))
            locations = result.locations
            categories = Self.normalizedCategories(result.categories)
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

        guard isAutoSyncEnabled else {
            syncIndicator = isConnected ? .idle : .offline
            return
        }

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
            categories: categories,
            pendingMutations: pendingMutations,
            syncState: syncState
        )
    }

    private func enqueueItemMutation(for item: InventoryItem, operation: InventoryPendingMutation.Operation) {
        pendingMutations.removeAll {
            $0.entityType == .item && $0.entityID == item.id.uuidString
        }
        pendingMutations.append(
            InventoryPendingMutation(
                entityType: .item,
                entityID: item.id.uuidString,
                operation: operation,
                item: item
            )
        )
    }

    private func enqueueLocationMutation(for location: InventoryLocationNode, operation: InventoryPendingMutation.Operation) {
        pendingMutations.removeAll {
            $0.entityType == .location && $0.entityID == location.id.uuidString
        }
        pendingMutations.append(
            InventoryPendingMutation(
                entityType: .location,
                entityID: location.id.uuidString,
                operation: operation,
                location: location
            )
        )
    }

    private func enqueueCategoryMutation(for category: InventoryCategory, operation: InventoryPendingMutation.Operation) {
        pendingMutations.removeAll {
            $0.entityType == .category && $0.entityID == category.id
        }
        pendingMutations.append(
            InventoryPendingMutation(
                entityType: .category,
                entityID: category.id,
                operation: operation,
                category: category
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

    private func normalizedItem(_ item: InventoryItem) -> InventoryItem {
        let categoryID = resolveCategoryID(for: item.category, fallbackName: nil)
        if categoryID == item.category {
            return item
        }

        return item.assigningCategory(categoryID)
    }

    private static func normalizedCategories(_ categories: [InventoryCategory]) -> [InventoryCategory] {
        let merged = defaultCategoriesMerged(with: categories.filter { !$0.isDeleted })
        let deleted = categories.filter(\.isDeleted)
        return merged + deleted
    }

    private static func defaultCategoriesMerged(with categories: [InventoryCategory]) -> [InventoryCategory] {
        var categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        for category in InventoryCategory.defaultCategories() where categoryMap[category.id] == nil {
            categoryMap[category.id] = category
        }
        return Array(categoryMap.values)
    }

    private static func legacyBuiltInCategoryLookup() -> [String: String] {
        [
            "appliances": String(localized: "inventory.category.appliances"),
            "cleaning": String(localized: "inventory.category.cleaning"),
            "electronics": String(localized: "inventory.category.electronics"),
            "furniture": String(localized: "inventory.category.furniture"),
            "kitchen": String(localized: "inventory.category.kitchen"),
            "office": String(localized: "inventory.category.office"),
            "supplies": String(localized: "inventory.category.supplies"),
            "textiles": String(localized: "inventory.category.textiles"),
            "tools": String(localized: "inventory.category.tools")
        ]
    }

    private func locationHasTreeMatch(_ location: InventoryLocationNode, query: String) -> Bool {
        if matchesSearch(location, query: query) {
            return true
        }

        if items(at: location.id).contains(where: { matchesSearch($0, query: query) }) {
            return true
        }

        return children(of: location.id).contains { locationHasTreeMatch($0, query: query) }
    }

    private func currentEditorIdentity() -> String? {
        let user = Auth.auth().currentUser
        return user?.email ?? user?.uid
    }

    deinit {
        remoteSync.stopListening()
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
    func assigningTag(_ tag: String?) -> InventoryItem {
        var copy = self
        copy.tag = tag
        return copy
    }

    func assigningCategory(_ categoryID: String) -> InventoryItem {
        var copy = self
        copy.category = categoryID
        return copy
    }

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
