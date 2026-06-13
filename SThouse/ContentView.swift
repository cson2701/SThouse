//
//  ContentView.swift
//  SThouse
//
//  Created by Gavin Song on 13/6/2026.
//

import SwiftUI

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
                                InventoryRow(
                                    item: item,
                                    locationLabel: viewModel.locationPathDescription(for: item.locationID)
                                ) {
                                    viewModel.activeSheet = .edit(item)
                                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !orphanItems.isEmpty {
                TreeNodeSection(
                    title: String(localized: "inventory.tree.unassigned"),
                    subtitle: String(localized: "inventory.tree.unassigned.subtitle"),
                    count: orphanItems.count,
                    isExpanded: true
                ) {
                    ForEach(orphanItems) { item in
                        InventoryLeafRow(item: item) {
                            onEditItem(item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                onDeleteItem(item)
                            } label: {
                                Label("inventory.delete", systemImage: "trash")
                            }
                            .tint(.red)
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
            subtitle: store.locationPathDescription(for: location.id),
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
            ForEach(directItems) { item in
                InventoryLeafRow(item: item) {
                    onEditItem(item)
                }
                .padding(.leading, 18)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        onDeleteItem(item)
                    } label: {
                        Label("inventory.delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }

            if isExpanded {
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
    let subtitle: String
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

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

private struct InventoryLeafRow: View {
    let item: InventoryItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func localizedCategoryName(for categoryCode: String) -> String {
        InventoryCategory(rawValue: categoryCode)?.localizedTitle ?? categoryCode
    }
}

private struct InventoryRow: View {
    let item: InventoryItem
    let locationLabel: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(InventoryRowButtonStyle())
    }

    private func localizedCategoryName(for categoryCode: String) -> String {
        InventoryCategory(rawValue: categoryCode)?.localizedTitle ?? categoryCode
    }
}

private struct InventoryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? Color.secondary.opacity(0.16) : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
