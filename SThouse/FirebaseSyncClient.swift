//
//  FirebaseSyncClient.swift
//  SThouse
//
//  Created by Codex on 27/6/2026.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

struct DisabledRemoteSyncClient: InventoryRemoteSyncing {
    let isEnabled = false

    func sync(snapshot: InventorySnapshot) async throws -> InventorySyncResult {
        InventorySyncResult(
            items: snapshot.items,
            locations: snapshot.locations,
            acknowledgedMutationIDs: [],
            syncedAt: snapshot.syncState.lastSuccessfulSyncAt ?? .now
        )
    }
}

struct FirebaseSyncClient: InventoryRemoteSyncing {
    private static let sharedHouseholdID = "shared-household"

    var isEnabled: Bool {
        Auth.auth().currentUser != nil
    }

    private let firestore: Firestore

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

        return try await InventorySyncResult(
            items: items.filter { !$0.isDeleted },
            locations: locations.filter { !$0.isDeleted },
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
                id: mutation.entityID,
                name: "",
                locationID: nil,
                category: InventoryCategory.unspecified.rawValue,
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
                id: mutation.entityID,
                name: "",
                parentID: nil,
                sortOrder: 0,
                isDeleted: mutation.operation == .delete,
                updatedAt: mutation.recordedAt
            )

            try await locationsCollection(householdID: householdID)
                .document(location.id.uuidString)
                .setData(location.firestoreData)
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
}

enum FirebaseSyncError: LocalizedError {
    case unauthenticated
    case invalidItemDocument(String)
    case invalidLocationDocument(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Sign in to enable cloud sync."
        case .invalidItemDocument(let id):
            return "Invalid item document \(id)."
        case .invalidLocationDocument(let id):
            return "Invalid location document \(id)."
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
