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
    @State private var isSearchBarVisible = false
    @State private var searchBarVisibilityTask: Task<Void, Never>?

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

                displayModeSection
                inventorySection
            }
            .dismissKeyboardOnTap()
            .navigationTitle("SThouse")
            .searchableIfNeeded(
                text: $viewModel.searchQuery,
                isEnabled: isSearchBarVisible && displayMode == .list,
                prompt: "Search items"
            )
            .onAppear {
                updateSearchBarVisibility(for: displayMode)
            }
            .onChange(of: displayMode) { _, newDisplayMode in
                updateSearchBarVisibility(for: newDisplayMode)
            }
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

                        Button("Sign out", role: .destructive) {
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
    private var displayModeSection: some View {
        Section {
            Picker("inventory.view.mode", selection: $displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    displayModeLabel(for: mode)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
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
                        viewModel.isShowingSearchResults ? "No matching items" : "inventory.empty.title",
                        systemImage: viewModel.isShowingSearchResults ? "magnifyingglass" : "shippingbox",
                        description: viewModel.isShowingSearchResults ? Text("Try a different search term.") : Text("inventory.empty.subtitle")
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

    private func updateSearchBarVisibility(for displayMode: DisplayMode) {
        searchBarVisibilityTask?.cancel()

        isSearchBarVisible = false

        guard displayMode == .list else {
            return
        }

        searchBarVisibilityTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            isSearchBarVisible = true
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

                Button("Sync", action: onSync)
                    .buttonStyle(.borderedProminent)
                    .disabled(indicator == .syncing || indicator == .disabled)
            }

            if pendingChangeCount > 0 {
                Text("\(pendingChangeCount) pending local change\(pendingChangeCount == 1 ? "" : "s")")
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
            return "Sign in to enable cloud sync."
        case .idle:
            if let lastSuccessfulSyncAt {
                return "Last sync \(lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Local data is ready."
        case .syncing:
            return "Pushing local changes and fetching the latest inventory."
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
                    onAddItem: onAddItemAtLocation,
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
    let onAddItem: (UUID) -> Void
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
            onContextAdd: {
                onAddItem(location.id)
            },
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
                        onAddItem: onAddItem,
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
    var onContextAdd: (() -> Void)? = nil
    var onToggle: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @State private var isPressed = false
    @State private var isShowingMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            .scaleEffect(isPressed ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isPressed)
            .onTapGesture {
                onToggle?()
            }
            .onLongPressGesture(
                minimumDuration: 0.35,
                pressing: { pressing in
                    withAnimation(.easeOut(duration: 0.14)) {
                        isPressed = pressing
                    }
                },
                perform: {
                    guard onContextAdd != nil else {
                        return
                    }

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
                if let onContextAdd {
                    Button {
                        onContextAdd()
                    } label: {
                        Label("inventory.addItem", systemImage: "plus")
                    }
                }
            }

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
                    .font(.body)

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

private extension View {
    @ViewBuilder
    func searchableIfNeeded(
        text: Binding<String>,
        isEnabled: Bool,
        prompt: LocalizedStringKey
    ) -> some View {
        if isEnabled {
            searchable(text: text, prompt: prompt)
        } else {
            self
        }
    }
}

#Preview {
    ContentView(authSession: FirebaseAuthSession())
}
