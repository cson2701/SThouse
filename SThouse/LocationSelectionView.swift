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

    var body: some View {
        NavigationStack {
            LocationLevelView(
                store: store,
                parentID: nil,
                selectedLocationID: $selectedLocationID,
                onSelectLeaf: {
                    dismiss()
                }
            )
            .navigationTitle("inventory.location.select")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("inventory.location.manage") {
                        isShowingManagement = true
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("inventory.cancel") {
                        dismiss()
                    }
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
    @Binding var selectedLocationID: UUID?
    let onSelectLeaf: () -> Void

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
                    if store.hasChildren(node.id) {
                        NavigationLink {
                            LocationLevelView(
                                store: store,
                                parentID: node.id,
                                selectedLocationID: $selectedLocationID,
                                onSelectLeaf: onSelectLeaf
                            )
                        } label: {
                            LocationNodeRow(
                                title: node.name,
                                subtitle: store.locationPathDescription(for: node.id),
                                isSelected: selectedLocationID == node.id,
                                showsChevron: true
                            )
                        }
                    } else {
                        Button {
                            selectedLocationID = node.id
                            onSelectLeaf()
                        } label: {
                            LocationNodeRow(
                                title: node.name,
                                subtitle: store.locationPathDescription(for: node.id),
                                isSelected: selectedLocationID == node.id,
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct LocationNodeRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let showsChevron: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
