//
//  ContentView.swift
//  SThouse
//
//  Created by Gavin Song on 13/6/2026.
//

import SwiftUI
import UIKit

struct ContentView: View {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case tree
        case list

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .tree:
                return "inventory.view.tree"
            case .list:
                return "inventory.view.list"
            }
        }
    }

    @State private var viewModel = InventoryListViewModel()
    @State private var isShowingLocationManagement = false
    @State private var displayMode: DisplayMode = .tree

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        SummaryCard(title: "inventory.summary.itemTypes", value: "\(viewModel.itemCount)")
                        SummaryCard(title: "inventory.summary.totalQuantity", value: "\(viewModel.totalQuantity)")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("inventory.view.mode", selection: $displayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                switch displayMode {
                case .tree:
                    Section("inventory.section.inventory") {
                        if viewModel.store.rootLocations.isEmpty && viewModel.store.items.isEmpty {
                            ContentUnavailableView(
                                "inventory.tree.empty.title",
                                systemImage: "tree",
                                description: Text("inventory.tree.empty.subtitle")
                            )
                        } else {
                            TreeInventoryView(
                                store: viewModel.store,
                                onEditItem: { viewModel.activeSheet = .edit($0) },
                                onDeleteItem: { viewModel.requestDelete($0) }
                            )
                        }
                    }
                case .list:
                    Section("inventory.section.inventory") {
                        if viewModel.items.isEmpty {
                            ContentUnavailableView(
                                "inventory.empty.title",
                                systemImage: "shippingbox",
                                description: Text("inventory.empty.subtitle")
                            )
                        } else {
                            ForEach(viewModel.items) { item in
                                listInventoryRow(for: item)
                                .transition(.opacity)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        viewModel.requestDelete(item)
                                    } label: {
                                        Label("inventory.delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("SThouse")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingLocationManagement = true
                    } label: {
                        Label("inventory.location.manage", systemImage: "square.grid.2x2")
                    }

                    Button {
                        viewModel.activeSheet = .add
                    } label: {
                        Label("inventory.addItem", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $viewModel.activeSheet) { sheet in
                switch sheet {
                case .add:
                    AddItemView(mode: .add, store: viewModel.store) { newItem in
                        viewModel.addItem(newItem)
                    }
                case .edit(let item):
                    AddItemView(mode: .edit, store: viewModel.store, onSave: { updatedItem in
                        viewModel.updateItem(updatedItem)
                    }, onDelete: {
                        viewModel.deleteItem(id: item.id)
                    }, item: item)
                }
            }
            .sheet(isPresented: $isShowingLocationManagement) {
                LocationManagementView(store: viewModel.store)
            }
            .alert(
                "inventory.delete.confirmation.title",
                isPresented: $viewModel.isShowingDeleteConfirmation,
                presenting: viewModel.pendingDeleteItem
            ) { item in
                Button("inventory.delete", role: .destructive) {
                    viewModel.confirmDelete()
                }

                Button("inventory.cancel", role: .cancel) {
                    viewModel.cancelDelete()
                }
            } message: { item in
                Text(verbatim: String(format: String(localized: "inventory.delete.confirmation.message"), item.name))
            }
        }
    }

    @ViewBuilder
    private func listInventoryRow(for item: InventoryItem) -> some View {
        InventoryRow(
            item: item,
            locationLabel: viewModel.locationPathDescription(for: item.locationID),
            onTap: {
                viewModel.activeSheet = .edit(item)
            },
            onDelete: {
                viewModel.requestDelete(item)
            }
        )
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct TreeInventoryView: View {
    let store: InventoryStore
    let onEditItem: (InventoryItem) -> Void
    let onDeleteItem: (InventoryItem) -> Void

    @State private var expandedLocationIDs: Set<UUID> = []
    @State private var isUnassignedExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !orphanItems.isEmpty {
                TreeNodeSection(
                    title: String(localized: "inventory.tree.unassigned"),
                    subtitle: String(localized: "inventory.tree.unassigned.subtitle"),
                    count: orphanItems.count,
                    isExpanded: isUnassignedExpanded,
                    onToggle: {
                        isUnassignedExpanded.toggle()
                    }
                ) {
                    if isUnassignedExpanded {
                        ForEach(orphanItems) { item in
                            InventoryLeafContextRow(item: item) {
                                onEditItem(item)
                            } onDelete: {
                                onDeleteItem(item)
                            }
                        }
                    }
                }
            }

            ForEach(store.rootLocations) { location in
                InventoryLocationTreeNode(
                    store: store,
                    location: location,
                    expandedLocationIDs: $expandedLocationIDs,
                    onEditItem: onEditItem,
                    onDeleteItem: onDeleteItem
                )
            }
        }
        .padding(.top, 4)
    }

    private var orphanItems: [InventoryItem] {
        store.items(at: nil)
    }
}

private struct InventoryLocationTreeNode: View {
    let store: InventoryStore
    let location: InventoryLocationNode
    @Binding var expandedLocationIDs: Set<UUID>
    let onEditItem: (InventoryItem) -> Void
    let onDeleteItem: (InventoryItem) -> Void

    var body: some View {
        let directItems = store.items(at: location.id)
        let children = store.children(of: location.id)
        let totalCount = store.totalItemCount(in: location.id)
        let isExpanded = expandedLocationIDs.contains(location.id)

        TreeNodeSection(
            title: location.name,
            subtitle: location.parentID == nil ? nil : store.locationPathDescription(for: location.id),
            count: totalCount,
            isExpanded: isExpanded,
            indentation: 0,
            onToggle: {
                if isExpanded {
                    expandedLocationIDs.remove(location.id)
                } else {
                    expandedLocationIDs.insert(location.id)
                }
            }
        ) {
            if isExpanded {
                ForEach(directItems) { item in
                    InventoryLeafContextRow(item: item) {
                        onEditItem(item)
                    } onDelete: {
                        onDeleteItem(item)
                    }
                    .padding(.leading, 28)
                }

                ForEach(children) { child in
                    InventoryLocationTreeNode(
                        store: store,
                        location: child,
                        expandedLocationIDs: $expandedLocationIDs,
                        onEditItem: onEditItem,
                        onDeleteItem: onDeleteItem
                    )
                    .padding(.leading, 18)
                }
            }
        }
    }
}

private struct TreeNodeSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let count: Int
    let isExpanded: Bool
    var indentation: CGFloat = 0
    var onToggle: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onToggle?()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)

                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            content()
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct InventoryLeafContextRow: View {
    let item: InventoryItem
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isPressed = false
    @State private var isShowingMenu = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body.weight(.medium))

                Text(localizedCategoryName(for: item.category))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text("x\(item.quantity)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isPressed ? 0.12 : 0), radius: isPressed ? 10 : 0, y: isPressed ? 4 : 0)
        .animation(.easeOut(duration: 0.14), value: isPressed)
        .onTapGesture(perform: onEdit)
        .onLongPressGesture(
            minimumDuration: 0.35,
            pressing: { pressing in
                withAnimation(.easeOut(duration: 0.14)) {
                    isPressed = pressing
                }
            },
            perform: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isPressed = false
                isShowingMenu = true
            }
        )
        .confirmationDialog(
            "",
            isPresented: $isShowingMenu,
            titleVisibility: .hidden
        ) {
            Button {
                onEdit()
            } label: {
                Label("inventory.editItem", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("inventory.delete", systemImage: "trash")
            }
        }
    }

    private func localizedCategoryName(for categoryCode: String) -> String {
        InventoryCategory(rawValue: categoryCode)?.localizedTitle ?? categoryCode
    }
}

private struct InventoryRow: View {
    let item: InventoryItem
    let locationLabel: String
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .font(.headline)

                Spacer()

                Text("x\(item.quantity)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }

            Text("\(locationLabel)  •  \(localizedCategoryName(for: item.category))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("inventory.editItem", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("inventory.delete", systemImage: "trash")
            }
        }
    }

    private func localizedCategoryName(for categoryCode: String) -> String {
        InventoryCategory(rawValue: categoryCode)?.localizedTitle ?? categoryCode
    }
}

#Preview {
    ContentView()
}
