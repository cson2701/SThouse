//
//  FirebaseSyncClient.swift
//  SThouse
//
//  Created by Codex on 27/6/2026.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

final class DisabledRemoteSyncClient: InventoryRemoteSyncing {
    let isEnabled = false

    func sync(snapshot: InventorySnapshot) async throws -> InventorySyncResult {
        InventorySyncResult(
            items: snapshot.items,
            locations: snapshot.locations,
            categories: snapshot.categories,
            acknowledgedMutationIDs: [],
            syncedAt: snapshot.syncState.lastSuccessfulSyncAt ?? .now
        )
    }

    func startListening(
        onUpdate: @escaping @Sendable (InventoryRemoteSnapshot) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {}

    func stopListening() {}
}

final class FirebaseSyncClient: InventoryRemoteSyncing {
    private static let sharedHouseholdID = "shared-household"

    var isEnabled: Bool {
        Auth.auth().currentUser != nil
    }

    private let firestore: Firestore
    private var itemListener: ListenerRegistration?
    private var locationListener: ListenerRegistration?
    private var categoryListener: ListenerRegistration?
    private var latestItems: [InventoryItem]?
    private var latestLocations: [InventoryLocationNode]?
    private var latestCategories: [InventoryCategory]?
    private var onUpdate: (@Sendable (InventoryRemoteSnapshot) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?

    init(firestore: Firestore = .firestore()) {
        self.firestore = firestore
    }

    func sync(snapshot: InventorySnapshot) async throws -> InventorySyncResult {
        let householdID = try currentHouseholdID()
        try await ensureHouseholdExists(householdID: householdID)

        for mutation in snapshot.pendingMutations.sorted(by: { $0.recordedAt < $1.recordedAt }) {
            try await apply(mutation, householdID: householdID)
        }

        async let items = fetchItems(householdID: householdID)
        async let locations = fetchLocations(householdID: householdID)
        async let categories = fetchCategories(householdID: householdID)

        return try await InventorySyncResult(
            items: items.filter { !$0.isDeleted },
            locations: locations.filter { !$0.isDeleted },
            categories: categories.filter { !$0.isDeleted },
            acknowledgedMutationIDs: snapshot.pendingMutations.map(\.id),
            syncedAt: .now
        )
    }

    private func currentHouseholdID() throws -> String {
        guard Auth.auth().currentUser != nil else {
            throw FirebaseSyncError.unauthenticated
        }

        return Self.sharedHouseholdID
    }

    private func ensureHouseholdExists(householdID: String) async throws {
        let user = try currentUser()
        let document = householdsCollection.document(householdID)

        try await document.setData([
            "ownerUid": user.uid,
            "email": user.email as Any,
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    private func apply(_ mutation: InventoryPendingMutation, householdID: String) async throws {
        switch mutation.entityType {
        case .item:
            let editorIdentity = try currentUser().email ?? currentUser().uid
            let item = mutation.item ?? InventoryItem(
                id: UUID(uuidString: mutation.entityID) ?? UUID(),
                name: "",
                locationID: nil,
                category: InventoryCategory.uncategorizedID,
                quantity: 0,
                lastEditedBy: editorIdentity,
                isDeleted: mutation.operation == .delete,
                updatedAt: mutation.recordedAt
            )

            try await itemsCollection(householdID: householdID)
                .document(item.id.uuidString)
                .setData(item.firestoreData)
        case .location:
            let location = mutation.location ?? InventoryLocationNode(
                id: UUID(uuidString: mutation.entityID) ?? UUID(),
                name: "",
                parentID: nil,
                sortOrder: 0,
                isDeleted: mutation.operation == .delete,
                updatedAt: mutation.recordedAt
            )

            try await locationsCollection(householdID: householdID)
                .document(location.id.uuidString)
                .setData(location.firestoreData)
        case .category:
            let category = mutation.category ?? InventoryCategory(
                id: mutation.entityID,
                name: "",
                sortOrder: 0,
                isDeleted: mutation.operation == .delete,
                updatedAt: mutation.recordedAt
            )

            try await categoriesCollection(householdID: householdID)
                .document(category.id)
                .setData(category.firestoreData)
        }
    }

    private func fetchItems(householdID: String) async throws -> [InventoryItem] {
        let snapshot = try await itemsCollection(householdID: householdID).getDocuments()
        return snapshot.documents.compactMap(InventoryItem.init(document:))
    }

    private func fetchLocations(householdID: String) async throws -> [InventoryLocationNode] {
        let snapshot = try await locationsCollection(householdID: householdID).getDocuments()
        return snapshot.documents.compactMap(InventoryLocationNode.init(document:))
    }

    private func fetchCategories(householdID: String) async throws -> [InventoryCategory] {
        let snapshot = try await categoriesCollection(householdID: householdID).getDocuments()
        return snapshot.documents.compactMap(InventoryCategory.init(document:))
    }

    private func currentUser() throws -> User {
        guard let user = Auth.auth().currentUser else {
            throw FirebaseSyncError.unauthenticated
        }

        return user
    }

    private var householdsCollection: CollectionReference {
        firestore.collection("households")
    }

    private func itemsCollection(householdID: String) -> CollectionReference {
        householdsCollection.document(householdID).collection("items")
    }

    private func locationsCollection(householdID: String) -> CollectionReference {
        householdsCollection.document(householdID).collection("locations")
    }

    private func categoriesCollection(householdID: String) -> CollectionReference {
        householdsCollection.document(householdID).collection("categories")
    }

    func startListening(
        onUpdate: @escaping @Sendable (InventoryRemoteSnapshot) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        stopListening()

        guard let householdID = try? currentHouseholdID() else {
            return
        }

        self.onUpdate = onUpdate
        self.onError = onError

        itemListener = itemsCollection(householdID: householdID).addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                self.onError?(error)
                return
            }

            guard let snapshot else {
                return
            }

            self.latestItems = snapshot.documents.compactMap(InventoryItem.init(document:)).filter { !$0.isDeleted }
            self.publishSnapshotIfReady()
        }

        locationListener = locationsCollection(householdID: householdID).addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                self.onError?(error)
                return
            }

            guard let snapshot else {
                return
            }

            self.latestLocations = snapshot.documents.compactMap(InventoryLocationNode.init(document:)).filter { !$0.isDeleted }
            self.publishSnapshotIfReady()
        }

        categoryListener = categoriesCollection(householdID: householdID).addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                self.onError?(error)
                return
            }

            guard let snapshot else {
                return
            }

            self.latestCategories = snapshot.documents.compactMap(InventoryCategory.init(document:)).filter { !$0.isDeleted }
            self.publishSnapshotIfReady()
        }
    }

    func stopListening() {
        itemListener?.remove()
        locationListener?.remove()
        categoryListener?.remove()
        itemListener = nil
        locationListener = nil
        categoryListener = nil
        latestItems = nil
        latestLocations = nil
        latestCategories = nil
        onUpdate = nil
        onError = nil
    }

    private func publishSnapshotIfReady() {
        guard let latestItems, let latestLocations, let latestCategories else {
            return
        }

        onUpdate?(
            InventoryRemoteSnapshot(
                items: latestItems,
                locations: latestLocations,
                categories: latestCategories,
                syncedAt: .now
            )
        )
    }

    deinit {
        stopListening()
    }
}

enum FirebaseSyncError: LocalizedError {
    case unauthenticated
    case invalidItemDocument(String)
    case invalidLocationDocument(String)
    case invalidCategoryDocument(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return String(localized: "inventory.sync.detail.disabled")
        case .invalidItemDocument(let id):
            return String.localizedStringWithFormat(String(localized: "inventory.sync.error.invalidItem"), id)
        case .invalidLocationDocument(let id):
            return String.localizedStringWithFormat(String(localized: "inventory.sync.error.invalidLocation"), id)
        case .invalidCategoryDocument(let id):
            return String.localizedStringWithFormat(String(localized: "inventory.sync.error.invalidCategory"), id)
        }
    }
}

private extension InventoryItem {
    var firestoreData: [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "locationId": locationID?.uuidString as Any,
            "category": category,
            "quantity": quantity,
            "tag": tag as Any,
            "lastEditedBy": lastEditedBy as Any,
            "deleted": isDeleted,
            "updatedAt": Timestamp(date: updatedAt),
            "serverUpdatedAt": FieldValue.serverTimestamp()
        ]
    }

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()

        guard
            let idString = data["id"] as? String,
            let id = UUID(uuidString: idString),
            let name = data["name"] as? String,
            let category = data["category"] as? String,
            let quantity = data["quantity"] as? Int,
            let isDeleted = data["deleted"] as? Bool,
            let updatedTimestamp = data["updatedAt"] as? Timestamp
        else {
            return nil
        }

        self.init(
            id: id,
            name: name,
            locationID: (data["locationId"] as? String).flatMap(UUID.init(uuidString:)),
            category: category,
            quantity: quantity,
            tag: data["tag"] as? String,
            lastEditedBy: data["lastEditedBy"] as? String,
            isDeleted: isDeleted,
            updatedAt: updatedTimestamp.dateValue(),
            serverUpdatedAt: (data["serverUpdatedAt"] as? Timestamp)?.dateValue()
        )
    }
}

private extension InventoryLocationNode {
    var firestoreData: [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "parentId": parentID?.uuidString as Any,
            "sortOrder": sortOrder,
            "deleted": isDeleted,
            "updatedAt": Timestamp(date: updatedAt),
            "serverUpdatedAt": FieldValue.serverTimestamp()
        ]
    }

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()

        guard
            let idString = data["id"] as? String,
            let id = UUID(uuidString: idString),
            let name = data["name"] as? String,
            let sortOrder = data["sortOrder"] as? Int,
            let isDeleted = data["deleted"] as? Bool,
            let updatedTimestamp = data["updatedAt"] as? Timestamp
        else {
            return nil
        }

        self.init(
            id: id,
            name: name,
            parentID: (data["parentId"] as? String).flatMap(UUID.init(uuidString:)),
            sortOrder: sortOrder,
            isDeleted: isDeleted,
            updatedAt: updatedTimestamp.dateValue(),
            serverUpdatedAt: (data["serverUpdatedAt"] as? Timestamp)?.dateValue()
        )
    }
}

private extension InventoryCategory {
    var firestoreData: [String: Any] {
        [
            "id": id,
            "name": name,
            "sortOrder": sortOrder,
            "deleted": isDeleted,
            "updatedAt": Timestamp(date: updatedAt),
            "serverUpdatedAt": FieldValue.serverTimestamp()
        ]
    }

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()

        guard
            let id = data["id"] as? String,
            let name = data["name"] as? String,
            let sortOrder = data["sortOrder"] as? Int,
            let isDeleted = data["deleted"] as? Bool,
            let updatedTimestamp = data["updatedAt"] as? Timestamp
        else {
            return nil
        }

        self.init(
            id: id,
            name: name,
            sortOrder: sortOrder,
            isDeleted: isDeleted,
            updatedAt: updatedTimestamp.dateValue(),
            serverUpdatedAt: (data["serverUpdatedAt"] as? Timestamp)?.dateValue()
        )
    }
}
