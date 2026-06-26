//
//  FirebaseSyncClient.swift
//  SThouse
//
//  Created by Codex on 27/6/2026.
//

import Foundation

struct FirebaseSyncConfiguration {
    let projectID: String
    let householdID: String
    let authToken: String

    init?(bundle: Bundle = .main) {
        guard
            let url = bundle.url(forResource: "FirebaseConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dictionary = object as? [String: Any],
            let projectID = dictionary["ProjectID"] as? String,
            let householdID = dictionary["HouseholdID"] as? String,
            let authToken = dictionary["AuthToken"] as? String,
            !projectID.isEmpty,
            !householdID.isEmpty,
            !authToken.isEmpty
        else {
            return nil
        }

        self.projectID = projectID
        self.householdID = householdID
        self.authToken = authToken
    }
}

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
    let isEnabled = true

    private let configuration: FirebaseSyncConfiguration
    private let session: URLSession

    init(configuration: FirebaseSyncConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func sync(snapshot: InventorySnapshot) async throws -> InventorySyncResult {
        try await push(mutations: snapshot.pendingMutations)
        let items = try await fetchItems()
        let locations = try await fetchLocations()

        return InventorySyncResult(
            items: items.filter { !$0.isDeleted },
            locations: locations.filter { !$0.isDeleted },
            acknowledgedMutationIDs: snapshot.pendingMutations.map(\.id),
            syncedAt: .now
        )
    }

    private func push(mutations: [InventoryPendingMutation]) async throws {
        guard !mutations.isEmpty else {
            return
        }

        let writes = mutations.map(makeWritePayload(for:))
        let body = ["writes": writes]

        var request = URLRequest(url: commitURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.authToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func fetchItems() async throws -> [InventoryItem] {
        let documents = try await listDocuments(collection: "items")
        return documents.compactMap(InventoryItem.init(document:))
    }

    private func fetchLocations() async throws -> [InventoryLocationNode] {
        let documents = try await listDocuments(collection: "locations")
        return documents.compactMap(InventoryLocationNode.init(document:))
    }

    private func listDocuments(collection: String) async throws -> [[String: Any]] {
        var request = URLRequest(url: collectionURL(named: collection))
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let documents = object["documents"] as? [[String: Any]]
        else {
            return []
        }

        return documents
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown Firebase response"
            throw FirebaseSyncError.invalidResponse(message)
        }
    }

    private func makeWritePayload(for mutation: InventoryPendingMutation) -> [String: Any] {
        let documentPath = documentName(for: mutation.entityType, id: mutation.entityID)

        switch mutation.entityType {
        case .item:
            let item = mutation.item ?? InventoryItem(
                id: mutation.entityID,
                name: "",
                locationID: nil,
                category: InventoryCategory.unspecified.rawValue,
                quantity: 0,
                isDeleted: true,
                updatedAt: mutation.recordedAt
            )

            return [
                "update": [
                    "name": documentPath,
                    "fields": item.firestoreFields
                ],
                "updateMask": [
                    "fieldPaths": Array(item.firestoreFields.keys).sorted()
                ],
                "updateTransforms": [
                    [
                        "fieldPath": "serverUpdatedAt",
                        "setToServerValue": "REQUEST_TIME"
                    ]
                ]
            ]
        case .location:
            let location = mutation.location ?? InventoryLocationNode(
                id: mutation.entityID,
                name: "",
                parentID: nil,
                sortOrder: 0,
                isDeleted: true,
                updatedAt: mutation.recordedAt
            )

            return [
                "update": [
                    "name": documentPath,
                    "fields": location.firestoreFields
                ],
                "updateMask": [
                    "fieldPaths": Array(location.firestoreFields.keys).sorted()
                ],
                "updateTransforms": [
                    [
                        "fieldPath": "serverUpdatedAt",
                        "setToServerValue": "REQUEST_TIME"
                    ]
                ]
            ]
        }
    }

    private func documentName(for entityType: InventoryPendingMutation.EntityType, id: UUID) -> String {
        let collectionName = entityType == .item ? "items" : "locations"
        return "\(documentRoot)/\(collectionName)/\(id.uuidString)"
    }

    private func collectionURL(named collection: String) -> URL {
        URL(string: "\(apiRoot)/\(documentRootPath)/\(collection)")!
    }

    private var commitURL: URL {
        URL(string: "\(apiRoot)/projects/\(configuration.projectID)/databases/(default)/documents:commit")!
    }

    private var apiRoot: String {
        "https://firestore.googleapis.com/v1"
    }

    private var documentRootPath: String {
        "projects/\(configuration.projectID)/databases/(default)/documents/households/\(configuration.householdID)"
    }

    private var documentRoot: String {
        "\(documentRootPath)"
    }
}

enum FirebaseSyncError: LocalizedError {
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return message
        }
    }
}

private extension InventoryItem {
    var firestoreFields: [String: Any] {
        var fields: [String: Any] = [
            "id": FirestoreField.string(id.uuidString),
            "name": FirestoreField.string(name),
            "category": FirestoreField.string(category),
            "quantity": FirestoreField.integer(quantity),
            "deleted": FirestoreField.boolean(isDeleted),
            "updatedAt": FirestoreField.timestamp(updatedAt)
        ]

        if let locationID {
            fields["locationId"] = FirestoreField.string(locationID.uuidString)
        } else {
            fields["locationId"] = FirestoreField.null
        }

        return fields
    }

    init?(document: [String: Any]) {
        guard
            let fields = document["fields"] as? [String: Any],
            let idString = fields.stringValue(for: "id"),
            let id = UUID(uuidString: idString),
            let name = fields.stringValue(for: "name"),
            let category = fields.stringValue(for: "category"),
            let quantity = fields.intValue(for: "quantity"),
            let isDeleted = fields.boolValue(for: "deleted"),
            let updatedAt = fields.dateValue(for: "updatedAt")
        else {
            return nil
        }

        self.init(
            id: id,
            name: name,
            locationID: fields.stringValue(for: "locationId").flatMap(UUID.init(uuidString:)),
            category: category,
            quantity: quantity,
            isDeleted: isDeleted,
            updatedAt: updatedAt,
            serverUpdatedAt: fields.dateValue(for: "serverUpdatedAt")
        )
    }
}

private extension InventoryLocationNode {
    var firestoreFields: [String: Any] {
        var fields: [String: Any] = [
            "id": FirestoreField.string(id.uuidString),
            "name": FirestoreField.string(name),
            "sortOrder": FirestoreField.integer(sortOrder),
            "deleted": FirestoreField.boolean(isDeleted),
            "updatedAt": FirestoreField.timestamp(updatedAt)
        ]

        if let parentID {
            fields["parentId"] = FirestoreField.string(parentID.uuidString)
        } else {
            fields["parentId"] = FirestoreField.null
        }

        return fields
    }

    init?(document: [String: Any]) {
        guard
            let fields = document["fields"] as? [String: Any],
            let idString = fields.stringValue(for: "id"),
            let id = UUID(uuidString: idString),
            let name = fields.stringValue(for: "name"),
            let sortOrder = fields.intValue(for: "sortOrder"),
            let isDeleted = fields.boolValue(for: "deleted"),
            let updatedAt = fields.dateValue(for: "updatedAt")
        else {
            return nil
        }

        self.init(
            id: id,
            name: name,
            parentID: fields.stringValue(for: "parentId").flatMap(UUID.init(uuidString:)),
            sortOrder: sortOrder,
            isDeleted: isDeleted,
            updatedAt: updatedAt,
            serverUpdatedAt: fields.dateValue(for: "serverUpdatedAt")
        )
    }
}

private extension Dictionary where Key == String, Value == Any {
    func stringValue(for key: String) -> String? {
        guard let value = self[key] as? [String: Any] else {
            return nil
        }

        return value["stringValue"] as? String
    }

    func intValue(for key: String) -> Int? {
        guard let value = self[key] as? [String: Any] else {
            return nil
        }

        if let intString = value["integerValue"] as? String {
            return Int(intString)
        }

        return value["integerValue"] as? Int
    }

    func boolValue(for key: String) -> Bool? {
        guard let value = self[key] as? [String: Any] else {
            return nil
        }

        return value["booleanValue"] as? Bool
    }

    func dateValue(for key: String) -> Date? {
        guard let value = self[key] as? [String: Any] else {
            return nil
        }

        if let timestamp = value["timestampValue"] as? String {
            return ISO8601DateFormatter.fractionalSeconds.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
        }

        return nil
    }
}

private enum FirestoreField {
    static func string(_ value: String) -> [String: Any] {
        ["stringValue": value]
    }

    static func integer(_ value: Int) -> [String: Any] {
        ["integerValue": "\(value)"]
    }

    static func boolean(_ value: Bool) -> [String: Any] {
        ["booleanValue": value]
    }

    static var null: [String: Any] {
        ["nullValue": NSNull()]
    }

    static func timestamp(_ value: Date) -> [String: Any] {
        ["timestampValue": ISO8601DateFormatter.fractionalSeconds.string(from: value)]
    }
}

private extension ISO8601DateFormatter {
    static let fractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
