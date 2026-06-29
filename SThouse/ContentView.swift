//
//  ContentView.swift
//  SThouse
//
//  Created by Gavin Song on 13/6/2026.
//

import Foundation
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    let authSession: FirebaseAuthSession

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
            VStack(spacing: 0) {
                displayModeHeader
                    .padding(.horizontal, Layout.displayModeHorizontalPadding)
                    .padding(.top, Layout.displayModeTopPadding)
                    .padding(.bottom, Layout.displayModeBottomPadding)

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
                        SyncStatusCard(
                            indicator: viewModel.syncIndicator,
                            pendingChangeCount: viewModel.pendingChangeCount,
                            lastSuccessfulSyncAt: viewModel.lastSuccessfulSyncAt,
                            onSync: {
                                Task {
                                    await viewModel.syncNow()
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    inventorySection
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("app.name")
            .searchable(text: $viewModel.searchQuery, prompt: "inventory.search.prompt")
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else {
                    return
                }

                Task {
                    await viewModel.syncNow()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if !authSession.userEmail.isEmpty {
                            Text(authSession.userEmail)
                        }

                        Button("auth.action.signOut", role: .destructive) {
                            authSession.signOut()
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    ToolbarActionButton(
                        systemImage: "square.grid.2x2",
                        accessibilityLabel: "inventory.location.manage"
                    ) {
                        isShowingLocationManagement = true
                    }

                    Button {
                        viewModel.activeSheet = .add(nil)
                    } label: {
                        Label("inventory.addItem", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $viewModel.activeSheet) { sheet in
                switch sheet {
                case .add(let locationID):
                    AddItemView(mode: .add, store: viewModel.store, onSave: { newItem in
                        viewModel.addItem(newItem)
                    }, initialLocationID: locationID)
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
            ) { _ in
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
    private var inventorySection: some View {
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
                        onAddItemAtLocation: { viewModel.activeSheet = .add($0) },
                        onEditItem: { viewModel.activeSheet = .edit($0) },
                        onDeleteItem: { viewModel.requestDelete($0) }
                    )
                }
            }
        case .list:
            Section("inventory.section.inventory") {
                if viewModel.filteredItems.isEmpty {
                    ContentUnavailableView(
                        viewModel.isShowingSearchResults ? "inventory.search.empty.title" : "inventory.empty.title",
                        systemImage: viewModel.isShowingSearchResults ? "magnifyingglass" : "shippingbox",
                        description: viewModel.isShowingSearchResults ? Text("inventory.search.empty.subtitle") : Text("inventory.empty.subtitle")
                    )
                } else {
                    ForEach(viewModel.filteredItems) { item in
                        listInventoryRow(for: item)
                            .transition(.opacity)
                            .listRowInsets(EdgeInsets())
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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

    private var displayModeHeader: some View {
        Picker("inventory.view.mode", selection: $displayMode) {
            ForEach(DisplayMode.allCases) { mode in
                displayModeLabel(for: mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private func displayModeLabel(for mode: DisplayMode) -> some View {
        Text(mode.title).tag(mode)
    }

    @ViewBuilder
    private func listInventoryRow(for item: InventoryItem) -> some View {
        InventoryRow(
            item: item,
            itemName: highlightedText(for: item.name, matching: viewModel.searchQuery),
            locationLabel: highlightedText(
                for: "\(viewModel.locationPathDescription(for: item.locationID))  •  \(localizedCategoryName(for: item.category))",
                matching: viewModel.searchQuery
            ),
            onTap: {
                viewModel.activeSheet = .edit(item)
            },
            onDelete: {
                viewModel.requestDelete(item)
            }
        )
    }

    private func highlightedText(for string: String, matching query: String) -> AttributedString {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var attributed = AttributedString(string)

        guard !trimmedQuery.isEmpty else {
            return attributed
        }

        var searchStart = string.startIndex
        while searchStart < string.endIndex,
              let matchRange = string.range(
                of: trimmedQuery,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<string.endIndex,
                locale: .current
              ) {
            if let attributedRange = Range(matchRange, in: attributed) {
                attributed[attributedRange].inlinePresentationIntent = .stronglyEmphasized
            }

            searchStart = matchRange.upperBound
        }

        return attributed
    }

    private func localizedCategoryName(for categoryCode: String) -> String {
        InventoryCategory(rawValue: categoryCode)?.localizedTitle ?? categoryCode
    }

    private enum Layout {
        static let displayModeHorizontalPadding: CGFloat = 16
        static let displayModeTopPadding: CGFloat = 8
        static let displayModeBottomPadding: CGFloat = 8
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

private struct SyncStatusCard: View {
    let indicator: InventorySyncIndicator
    let pendingChangeCount: Int
    let lastSuccessfulSyncAt: Date?
    let onSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: indicator.systemImageName)
                    .foregroundStyle(iconColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(indicator.title)
                        .font(.headline)

                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button("inventory.sync.action", action: onSync)
                    .buttonStyle(.borderedProminent)
                    .disabled(indicator == .syncing || indicator == .disabled)
            }

            if pendingChangeCount > 0 {
                Text(String.localizedStringWithFormat(String(localized: "inventory.sync.pendingChanges"), pendingChangeCount))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var detailText: String {
        switch indicator {
        case .disabled:
            return String(localized: "inventory.sync.detail.disabled")
        case .idle:
            if let lastSuccessfulSyncAt {
                return String.localizedStringWithFormat(
                    String(localized: "inventory.sync.detail.lastSync"),
                    lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
            return String(localized: "inventory.sync.detail.ready")
        case .syncing:
            return String(localized: "inventory.sync.detail.syncing")
        case .failed(let message):
            return message
        }
    }

    private var iconColor: Color {
        switch indicator {
        case .disabled:
            .secondary
        case .idle:
            .green
        case .syncing:
            .blue
        case .failed:
            .orange
        }
    }
}

private struct TreeInventoryView: View {
    let store: InventoryStore
    let onAddItemAtLocation: (UUID) -> Void
    let onEditItem: (InventoryItem) -> Void
    let onDeleteItem: (InventoryItem) -> Void
    @State private var expandedRowIDs: Set<String> = ["unassigned"]

    var body: some View {
        ForEach(treeRows) { row in
            TreeInventoryRow(
                row: row,
                expandedRowIDs: $expandedRowIDs,
                onAddItemAtLocation: onAddItemAtLocation,
                onEditItem: onEditItem,
                onDeleteItem: onDeleteItem
            )
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private var orphanItems: [InventoryItem] {
        store.items(at: nil)
    }

    private var treeRows: [TreeInventoryRowModel] {
        var rows = store.rootLocations.map(makeLocationRow)

        if !orphanItems.isEmpty {
            rows.insert(
                .unassigned(
                    title: String(localized: "inventory.tree.unassigned"),
                    subtitle: String(localized: "inventory.tree.unassigned.subtitle"),
                    count: orphanItems.count,
                    children: orphanItems.map(TreeInventoryRowModel.item)
                ),
                at: 0
            )
        }

        return rows
    }

    private func makeLocationRow(_ location: InventoryLocationNode) -> TreeInventoryRowModel {
        let childLocations = store.children(of: location.id).map(makeLocationRow)
        let directItems = store.items(at: location.id).map(TreeInventoryRowModel.item)

        return .location(
            location,
            subtitle: location.parentID == nil ? nil : store.locationPathDescription(for: location.id),
            count: store.totalItemCount(in: location.id),
            children: childLocations + directItems
        )
    }
}

private enum TreeInventoryRowModel: Identifiable {
    case location(InventoryLocationNode, subtitle: String?, count: Int, children: [TreeInventoryRowModel])
    case item(InventoryItem)
    case unassigned(title: String, subtitle: String, count: Int, children: [TreeInventoryRowModel])

    var id: String {
        switch self {
        case .location(let location, _, _, _):
            return "location-\(location.id.uuidString)"
        case .item(let item):
            return "item-\(item.id.uuidString)"
        case .unassigned:
            return "unassigned"
        }
    }

    var children: [TreeInventoryRowModel]? {
        switch self {
        case .location(_, _, _, let children), .unassigned(_, _, _, let children):
            children.isEmpty ? nil : children
        case .item:
            nil
        }
    }
}

private struct TreeInventoryRow: View {
    let row: TreeInventoryRowModel
    @Binding var expandedRowIDs: Set<String>
    let onAddItemAtLocation: (UUID) -> Void
    let onEditItem: (InventoryItem) -> Void
    let onDeleteItem: (InventoryItem) -> Void
    @State private var isShowingMenu = false

    var body: some View {
        switch row {
        case .location(let location, let subtitle, let count, let children):
            DisclosureGroup(isExpanded: expansionBinding(for: row.id)) {
                ForEach(children) { child in
                    TreeInventoryRow(
                        row: child,
                        expandedRowIDs: $expandedRowIDs,
                        onAddItemAtLocation: onAddItemAtLocation,
                        onEditItem: onEditItem,
                        onDeleteItem: onDeleteItem
                    )
                }
            } label: {
                rowLabel(
                    icon: location.parentID == nil ? "door.left.hand.open" : "cabinet.fill",
                    title: location.name,
                    subtitle: subtitle,
                    trailingText: "\(count)"
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleExpansion(for: row.id)
                }
                .onLongPressGesture(minimumDuration: 0.35) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isShowingMenu = true
                }
            }
            .confirmationDialog("", isPresented: $isShowingMenu, titleVisibility: .hidden) {
                Button {
                    onAddItemAtLocation(location.id)
                } label: {
                    Label("inventory.addItem", systemImage: "plus")
                }
            }
        case .item(let item):
            rowLabel(
                icon: "shippingbox.fill",
                title: item.name,
                subtitle: localizedCategoryName(for: item.category),
                trailingText: "x\(item.quantity)"
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onEditItem(item)
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isShowingMenu = true
            }
            .confirmationDialog("", isPresented: $isShowingMenu, titleVisibility: .hidden) {
                Button {
                    onEditItem(item)
                } label: {
                    Label("inventory.editItem", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDeleteItem(item)
                } label: {
                    Label("inventory.delete", systemImage: "trash")
                }
            }
        case .unassigned(let title, let subtitle, let count, let children):
            DisclosureGroup(isExpanded: expansionBinding(for: row.id)) {
                ForEach(children) { child in
                    TreeInventoryRow(
                        row: child,
                        expandedRowIDs: $expandedRowIDs,
                        onAddItemAtLocation: onAddItemAtLocation,
                        onEditItem: onEditItem,
                        onDeleteItem: onDeleteItem
                    )
                }
            } label: {
                rowLabel(
                    icon: "tray.full.fill",
                    title: title,
                    subtitle: subtitle,
                    trailingText: "\(count)"
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleExpansion(for: row.id)
                }
            }
        }
    }

    private func expansionBinding(for rowID: String) -> Binding<Bool> {
        Binding(
            get: {
                expandedRowIDs.contains(rowID)
            },
            set: { isExpanded in
                if isExpanded {
                    expandedRowIDs.insert(rowID)
                } else {
                    expandedRowIDs.remove(rowID)
                }
            }
        )
    }

    private func toggleExpansion(for rowID: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedRowIDs.contains(rowID) {
                expandedRowIDs.remove(rowID)
            } else {
                expandedRowIDs.insert(rowID)
            }
        }
    }

    private func rowLabel(icon: String, title: String, subtitle: String?, trailingText: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Text(trailingText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func localizedCategoryName(for categoryCode: String) -> String {
        InventoryCategory(rawValue: categoryCode)?.localizedTitle ?? categoryCode
    }
}

private struct InventoryRow: View {
    let item: InventoryItem
    let itemName: AttributedString
    let locationLabel: AttributedString
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(itemName)
                        .font(.body)

                    Spacer()

                    Text("x\(item.quantity)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }

                Text(locationLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
        }
        .buttonStyle(InventoryRowButtonStyle())
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
}

private struct InventoryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ContentView(authSession: FirebaseAuthSession())
}
