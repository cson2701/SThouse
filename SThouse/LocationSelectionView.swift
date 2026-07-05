//
//  LocationSelectionView.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import SwiftUI

struct LocationSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let store: InventoryStore
    @Binding var selectedLocationID: UUID?

    @State private var isShowingManagement = false
    @State private var navigationPath: [UUID] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            LocationLevelView(
                store: store,
                parentID: nil,
                currentLocationID: nil,
                selectedLocationID: $selectedLocationID,
                onConfirmSelection: { dismiss() },
                onManageLocations: { isShowingManagement = true }
            )
            .navigationDestination(for: UUID.self) { locationID in
                LocationLevelView(
                    store: store,
                    parentID: locationID,
                    currentLocationID: locationID,
                    selectedLocationID: $selectedLocationID,
                    onConfirmSelection: { dismiss() },
                    onManageLocations: { isShowingManagement = true }
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("inventory.cancel"))
                }
            }
            .sheet(isPresented: $isShowingManagement) {
                LocationManagementView(store: store)
            }
        }
    }
}

private struct LocationLevelView: View {
    let store: InventoryStore
    let parentID: UUID?
    let currentLocationID: UUID?
    @Binding var selectedLocationID: UUID?
    let onConfirmSelection: () -> Void
    let onManageLocations: () -> Void

    @State private var draftSelectedLocationID: UUID?
    @State private var lockedSelectionID: UUID?

    init(
        store: InventoryStore,
        parentID: UUID?,
        currentLocationID: UUID?,
        selectedLocationID: Binding<UUID?>,
        onConfirmSelection: @escaping () -> Void,
        onManageLocations: @escaping () -> Void
    ) {
        self.store = store
        self.parentID = parentID
        self.currentLocationID = currentLocationID
        self._selectedLocationID = selectedLocationID
        self.onConfirmSelection = onConfirmSelection
        self.onManageLocations = onManageLocations

        let initialSelection = store.children(of: parentID).first { $0.id == selectedLocationID.wrappedValue }?.id
        _draftSelectedLocationID = State(initialValue: initialSelection)
        _lockedSelectionID = State(initialValue: selectedLocationID.wrappedValue)
    }

    private var hasSelectionOnCurrentScreen: Bool {
        guard let draftSelectedLocationID else {
            return false
        }

        return draftSelectedLocationID != lockedSelectionID
    }

    var body: some View {
        List {
            let children = store.children(of: parentID)
            if children.isEmpty {
                ContentUnavailableView(
                    "inventory.location.empty.title",
                    systemImage: "house",
                    description: Text("inventory.location.empty.subtitle")
                )
            } else {
                ForEach(children) { node in
                    LocationSelectionRow(
                        store: store,
                        node: node,
                        selectedLocationID: $draftSelectedLocationID,
                        lockedSelectionID: $lockedSelectionID
                    )
                }
            }
        }
        .navigationTitle(currentLocationID.map { store.location(id: $0)?.name ?? String(localized: "inventory.location.select") } ?? String(localized: "inventory.location.select"))
        .listStyle(.insetGrouped)
        .toolbar {
            if currentLocationID != nil {
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarActionButton(
                        systemImage: "checkmark",
                        accessibilityLabel: "inventory.location.selectCurrent",
                        style: .prominentBlue
                    ) {
                        selectedLocationID = draftSelectedLocationID
                        onConfirmSelection()
                    }
                    .disabled(!hasSelectionOnCurrentScreen)
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    if hasSelectionOnCurrentScreen {
                        ToolbarActionButton(
                            systemImage: "checkmark",
                            accessibilityLabel: "inventory.location.selectCurrent",
                            style: .prominentBlue
                        ) {
                            selectedLocationID = draftSelectedLocationID
                            onConfirmSelection()
                        }
                    } else {
                        ToolbarActionButton(
                            systemImage: "square.grid.2x2",
                            accessibilityLabel: "inventory.location.manage"
                        ) {
                            onManageLocations()
                        }
                    }
                }
            }
        }
    }
}

private struct LocationNodeRow: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private struct LocationSelectionRow: View {
    let store: InventoryStore
    let node: InventoryLocationNode
    @Binding var selectedLocationID: UUID?
    @Binding var lockedSelectionID: UUID?

    private var isSelected: Bool {
        selectedLocationID == node.id
    }

    private var isLocked: Bool {
        lockedSelectionID == node.id && selectedLocationID == lockedSelectionID
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                guard !isLocked else {
                    return
                }

                if lockedSelectionID != nil, lockedSelectionID != node.id {
                    lockedSelectionID = nil
                }

                selectedLocationID = isSelected ? nil : node.id
            } label: {
                if isSelected && isLocked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLocked)
            .accessibilityLabel(Text(isSelected ? "inventory.location.deselectNode" : "inventory.location.selectNode"))

            if store.hasChildren(node.id) {
                NavigationLink(value: node.id) {
                    LocationNodeRow(
                        title: node.name,
                        subtitle: node.parentID == nil ? nil : store.locationPathDescription(for: node.id)
                    )
                }
            } else {
                LocationNodeRow(
                    title: node.name,
                    subtitle: node.parentID == nil ? nil : store.locationPathDescription(for: node.id)
                )
            }
        }
    }
}
