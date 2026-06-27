//
//  LocationManagementView.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import SwiftUI

struct LocationManagementView: View {
    @Environment(\.dismiss) private var dismiss
    let store: InventoryStore

    @State private var editorTarget: LocationEditorTarget?
    @State private var deleteTarget: InventoryLocationNode?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.rootLocations.isEmpty {
                        ContentUnavailableView(
                            "inventory.location.manage.empty.title",
                            systemImage: "square.and.pencil",
                            description: Text("inventory.location.manage.empty.subtitle")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    } else {
                        ForEach(store.rootLocations) { node in
                            LocationTreeEditorRow(
                                node: node,
                                depth: 0,
                                store: store,
                                onAddChild: { editorTarget = .add(parentID: $0.id) },
                                onRename: { editorTarget = .rename(node: $0) },
                                onDelete: { target in
                                    deleteTarget = target
                                    isShowingDeleteConfirmation = true
                                }
                            )
                        }
                    }
                }
                .padding()
            }
            .dismissKeyboardOnTap()
            .navigationTitle("inventory.location.manage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarActionButton(
                        systemImage: "xmark",
                        accessibilityLabel: "inventory.cancel"
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorTarget = .add(parentID: nil)
                    } label: {
                        Label("inventory.location.addRoot", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                LocationEditorSheet(
                    store: store,
                    target: target
                )
            }
            .alert(
                "inventory.location.delete.title",
                isPresented: $isShowingDeleteConfirmation,
                presenting: deleteTarget
            ) { node in
                Button("inventory.delete", role: .destructive) {
                    store.deleteLocationSubtree(id: node.id)
                }

                Button("inventory.cancel", role: .cancel) {
                }
            } message: { node in
                Text("inventory.location.delete.message")
            }
        }
    }
}

private struct LocationTreeEditorRow: View {
    let node: InventoryLocationNode
    let depth: Int
    let store: InventoryStore
    let onAddChild: (InventoryLocationNode) -> Void
    let onRename: (InventoryLocationNode) -> Void
    let onDelete: (InventoryLocationNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name)
                        .font(.headline)

                    if let subtitle = node.parentID == nil ? nil : store.locationPathDescription(for: node.id) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                Menu {
                    Button("inventory.location.addChild") {
                        onAddChild(node)
                    }

                    Button("inventory.location.rename") {
                        onRename(node)
                    }

                    Button("inventory.delete", role: .destructive) {
                        onDelete(node)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            ForEach(store.children(of: node.id)) { child in
                LocationTreeEditorRow(
                    node: child,
                    depth: depth + 1,
                    store: store,
                    onAddChild: onAddChild,
                    onRename: onRename,
                    onDelete: onDelete
                )
                .padding(.leading, 16)
            }
        }
    }
}

private struct LocationEditorTarget: Identifiable {
    enum Mode {
        case add(parentID: UUID?)
        case rename(node: InventoryLocationNode)
    }

    let id = UUID()
    let mode: Mode

    static func add(parentID: UUID?) -> LocationEditorTarget {
        LocationEditorTarget(mode: .add(parentID: parentID))
    }

    static func rename(node: InventoryLocationNode) -> LocationEditorTarget {
        LocationEditorTarget(mode: .rename(node: node))
    }
}

private struct LocationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let store: InventoryStore
    let target: LocationEditorTarget

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("inventory.location.name", text: $name)
                } header: {
                    Text(headerTitle)
                } footer: {
                    footerText
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(sheetTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarActionButton(
                        systemImage: "xmark",
                        accessibilityLabel: "inventory.cancel"
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    ToolbarActionButton(
                        systemImage: "checkmark",
                        accessibilityLabel: "inventory.save",
                        style: .prominentBlue
                    ) {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            switch target.mode {
            case .add:
                break
            case .rename(let node):
                name = node.name
            }
        }
    }

    private var sheetTitle: LocalizedStringKey {
        switch target.mode {
        case .add:
            return "inventory.location.add"
        case .rename:
            return "inventory.location.rename"
        }
    }

    private var headerTitle: LocalizedStringKey {
        switch target.mode {
        case .add:
            return "inventory.location.name"
        case .rename:
            return "inventory.location.newName"
        }
    }

    private var footerText: Text {
        switch target.mode {
        case .add(let parentID):
            if let parentID, let parent = store.location(id: parentID) {
                return Text(String(format: String(localized: "inventory.location.parent"), parent.name))
            }

            return Text("inventory.location.parent.root")
        case .rename(let node):
            return Text(String(format: String(localized: "inventory.location.rename.footer"), node.name))
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        switch target.mode {
        case .add(let parentID):
            _ = store.addLocation(name: trimmedName, parentID: parentID)
        case .rename(let node):
            store.renameLocation(id: node.id, name: trimmedName)
        }

        dismiss()
    }
}
