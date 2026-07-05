//
//  ContentView.swift
//  SThouse
//
//  Created by Gavin Song on 13/6/2026.
//

import Foundation
import SwiftUI

private enum InventoryLayout {
    static let rowInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
}

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
    @State private var isShowingSettings = false
    @State private var isShowingSyncStatusPopup = false
    @State private var isShowingLocationManagement = false
    @State private var isShowingCategoryManagement = false
    @State private var displayMode: DisplayMode = .tree
    @State private var pagedDisplayMode: DisplayMode? = .tree
    @State private var treeViewportFrame: CGRect = .zero
    @State private var treeRowFrames: [String: CGRect] = [:]
    @State private var pendingTreeScrollRowIDs: [String] = []

    var body: some View {
        NavigationStack {
            inventoryList
            .dismissKeyboardOnTap()
            .navigationTitle("app.name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar, .tabBar)
            .searchable(text: $viewModel.searchQuery, prompt: "inventory.search.prompt")
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, viewModel.isAutoSyncEnabled else {
                    return
                }

                Task {
                    await viewModel.syncNow()
                }
            }
            .onChange(of: displayMode) { _, newMode in
                guard pagedDisplayMode != newMode else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.25)) {
                    pagedDisplayMode = newMode
                }
            }
            .onChange(of: pagedDisplayMode) { _, newMode in
                guard let newMode, displayMode != newMode else {
                    return
                }

                displayMode = newMode
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }

                ToolbarItem(placement: .principal) {
                    displayModeNavigationControl
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.activeSheet = .add(nil)
                    } label: {
                        Label("inventory.addItem", systemImage: "plus")
                    }

                    Menu {
                        Button("inventory.location.manage") {
                            isShowingLocationManagement = true
                        }

                        Button("inventory.category.manage") {
                            isShowingCategoryManagement = true
                        }

                        Menu("Debug") {
                            Button("Add Demo Data") {
                                viewModel.addDemoData()
                            }

                            Button("Delete Demo Items", role: .destructive) {
                                viewModel.deleteDemoItems()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
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
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(
                    authSession: authSession,
                    isAutoSyncEnabled: autoSyncBinding
                )
            }
            .sheet(isPresented: $isShowingSyncStatusPopup) {
                SyncStatusPopupView(
                    indicator: viewModel.syncIndicator,
                    pendingChangeCount: viewModel.pendingChangeCount,
                    lastSuccessfulSyncAt: viewModel.lastSuccessfulSyncAt,
                    onSync: {
                        Task {
                            await viewModel.syncNow()
                        }
                    }
                )
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingLocationManagement) {
                LocationManagementView(store: viewModel.store)
            }
            .sheet(isPresented: $isShowingCategoryManagement) {
                CategoryManagementView(store: viewModel.store)
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

    private var displayModeNavigationControl: some View {
        Picker("inventory.view.mode", selection: animatedDisplayModeBinding) {
            ForEach(DisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
            .frame(maxWidth: Layout.displayModeControlMaxWidth)
    }

    private var animatedDisplayModeBinding: Binding<DisplayMode> {
        Binding(
            get: { displayMode },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.25)) {
                    displayMode = newValue
                }
            }
        )
    }

    private var inventoryList: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    inventoryList(for: .tree)
                        .frame(width: geometry.size.width)
                        .id(DisplayMode.tree)

                    inventoryList(for: .list)
                        .frame(width: geometry.size.width)
                        .id(DisplayMode.list)
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pagedDisplayMode)
        }
    }

    private func inventoryList(for mode: DisplayMode) -> some View {
        ScrollViewReader { proxy in
            List {
                summarySection
                syncSection
                inventorySection(for: mode, scrollProxy: proxy)
            }
            .background {
                if mode == .tree {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: TreeViewportFramePreferenceKey.self,
                            value: geometry.frame(in: .global)
                        )
                    }
                }
            }
            .onPreferenceChange(TreeViewportFramePreferenceKey.self) { frame in
                guard mode == .tree else {
                    return
                }

                treeViewportFrame = frame
                resolvePendingTreeScroll(with: proxy)
            }
            .onPreferenceChange(TreeRowFramePreferenceKey.self) { frames in
                guard mode == .tree else {
                    return
                }

                treeRowFrames = frames
                resolvePendingTreeScroll(with: proxy)
            }
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 16) {
                SummaryCard(title: "inventory.summary.itemTypes", value: "\(viewModel.itemCount)")
                SummaryCard(title: "inventory.summary.totalQuantity", value: "\(viewModel.totalQuantity)")

                if viewModel.isAutoSyncEnabled {
                    Button {
                        isShowingSyncStatusPopup = true
                    } label: {
                        CompactSyncStatusCard(
                            systemImageName: viewModel.syncIndicator.systemImageName,
                            tintColor: syncIndicatorColor
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(viewModel.syncIndicator.title))
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var syncSection: some View {
        Section {
            if !viewModel.isAutoSyncEnabled {
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
        }
    }

    private var autoSyncBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isAutoSyncEnabled },
            set: { viewModel.setAutoSyncEnabled($0) }
        )
    }

    private var syncIndicatorColor: Color {
        switch viewModel.syncIndicator {
        case .disabled:
            .secondary
        case .idle:
            .green
        case .offline:
            .orange
        case .syncing:
            .blue
        case .failed:
            .orange
        }
    }

    @ViewBuilder
    private func inventorySection(for mode: DisplayMode, scrollProxy: ScrollViewProxy) -> some View {
        switch mode {
        case .tree:
            Section("inventory.section.inventory") {
                if !viewModel.store.hasTreeMatches(for: viewModel.searchQuery) {
                    ContentUnavailableView(
                        viewModel.isShowingSearchResults ? "inventory.search.empty.title" : "inventory.tree.empty.title",
                        systemImage: viewModel.isShowingSearchResults ? "magnifyingglass" : "tree",
                        description: viewModel.isShowingSearchResults ? Text("inventory.search.empty.subtitle") : Text("inventory.tree.empty.subtitle")
                    )
                } else {
                    TreeInventoryView(
                        store: viewModel.store,
                        searchQuery: viewModel.searchQuery,
                        categoryName: viewModel.categoryName(for:),
                        onAddItemAtLocation: { viewModel.activeSheet = .add($0) },
                        onEditItem: { viewModel.activeSheet = .edit($0) },
                        onDeleteItem: { viewModel.requestDelete($0) },
                        onExpandToRowIDs: { rowIDs in
                            pendingTreeScrollRowIDs = rowIDs
                            resolvePendingTreeScroll(with: scrollProxy)
                        }
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

    @ViewBuilder
    private func listInventoryRow(for item: InventoryItem) -> some View {
        InventoryRow(
            item: item,
            itemName: makeHighlightedText(
                for: item.name,
                matching: viewModel.searchQuery,
                baseColor: .primary,
                dimmedColor: .secondary.opacity(0.72)
            ),
            locationLabel: makeHighlightedText(
                for: "\(viewModel.locationPathDescription(for: item.locationID))  •  \(viewModel.categoryName(for: item.category))",
                matching: viewModel.searchQuery,
                baseColor: .secondary,
                dimmedColor: .secondary.opacity(0.65)
            ),
            onTap: {
                viewModel.activeSheet = .edit(item)
            },
            onDelete: {
                viewModel.requestDelete(item)
            }
        )
    }

    private enum Layout {
        static let displayModeControlMaxWidth: CGFloat = 160
        static let treeScrollTopPadding: CGFloat = 12
        static let treeScrollBottomPadding: CGFloat = 24
    }

    private func resolvePendingTreeScroll(with scrollProxy: ScrollViewProxy) {
        guard displayMode == .tree, !pendingTreeScrollRowIDs.isEmpty else {
            return
        }

        guard treeViewportFrame != .zero else {
            return
        }

        let topBoundary = treeViewportFrame.minY + Layout.treeScrollTopPadding
        let bottomBoundary = treeViewportFrame.maxY - Layout.treeScrollBottomPadding
        let candidateFrames = pendingTreeScrollRowIDs.compactMap { rowID in
            treeRowFrames[rowID].map { (rowID: rowID, frame: $0) }
        }

        guard !candidateFrames.isEmpty else {
            return
        }

        if let topHiddenRowID = candidateFrames.first(where: { $0.frame.minY < topBoundary })?.rowID {
            pendingTreeScrollRowIDs = []
            withAnimation(.easeInOut(duration: 0.2)) {
                scrollProxy.scrollTo(topHiddenRowID, anchor: .center)
            }
        } else if let bottomHiddenRowID = candidateFrames.last(where: { $0.frame.maxY > bottomBoundary })?.rowID {
            pendingTreeScrollRowIDs = []
            withAnimation(.easeInOut(duration: 0.2)) {
                scrollProxy.scrollTo(bottomHiddenRowID, anchor: .bottom)
            }
        } else {
            pendingTreeScrollRowIDs = []
        }
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let authSession: FirebaseAuthSession
    @Binding var isAutoSyncEnabled: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.account") {
                    LabeledContent("settings.user.name", value: userName)
                    LabeledContent("settings.user.email", value: userEmail)
                }

                Section("settings.sync") {
                    Toggle("settings.sync.auto", isOn: $isAutoSyncEnabled)
                }

                Section {
                    Button("auth.action.signOut", role: .destructive) {
                        authSession.signOut()
                        dismiss()
                    }
                }
            }
            .navigationTitle("settings.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarActionButton(
                        systemImage: "xmark",
                        accessibilityLabel: "inventory.cancel"
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var userName: String {
        if !authSession.userDisplayName.isEmpty {
            return authSession.userDisplayName
        }

        if !authSession.userEmail.isEmpty {
            return authSession.userEmail
        }

        return String(localized: "settings.user.unknown")
    }

    private var userEmail: String {
        if !authSession.userEmail.isEmpty {
            return authSession.userEmail
        }

        return String(localized: "settings.user.unknown")
    }
}

private struct SyncStatusPopupView: View {
    let indicator: InventorySyncIndicator
    let pendingChangeCount: Int
    let lastSuccessfulSyncAt: Date?
    let onSync: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: indicator.systemImageName)
                        .foregroundStyle(iconColor)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(indicator.title)
                            .font(.headline)

                        Text(detailText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button("inventory.sync.action", action: onSync)
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            indicator == .syncing
                                || indicator == .disabled
                                || indicator == .offline
                        )
                }

                if pendingChangeCount > 0 {
                    Text(String.localizedStringWithFormat(String(localized: "inventory.sync.pendingChanges"), pendingChangeCount))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .navigationTitle("inventory.sync.popup.title")
            .navigationBarTitleDisplayMode(.inline)
        }
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
        case .offline:
            return String(localized: "inventory.sync.detail.offline")
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
        case .offline:
            .orange
        case .syncing:
            .blue
        case .failed:
            .orange
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
        .inventoryCardSurface()
    }
}

private struct CompactSyncStatusCard: View {
    let systemImageName: String
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("inventory.sync.popup.title")
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: systemImageName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tintColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .inventoryCardSurface()
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
                    .disabled(
                        indicator == .syncing
                            || indicator == .disabled
                            || indicator == .offline
                    )
            }

            if pendingChangeCount > 0 {
                Text(String.localizedStringWithFormat(String(localized: "inventory.sync.pendingChanges"), pendingChangeCount))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .inventoryCardSurface()
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
        case .offline:
            return String(localized: "inventory.sync.detail.offline")
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
        case .offline:
            .orange
        case .syncing:
            .blue
        case .failed:
            .orange
        }
    }
}

private struct InventoryCardSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        content
            .background(cardBackground, in: shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: 1)
            }
    }

    private var cardBackground: Color {
        switch colorScheme {
        case .light:
            return Color(uiColor: .systemBackground)
        case .dark:
            return Color(uiColor: .secondarySystemBackground)
        @unknown default:
            return Color(uiColor: .systemBackground)
        }
    }

    private var borderColor: Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.06)
        case .dark:
            return Color.white.opacity(0.08)
        @unknown default:
            return Color.black.opacity(0.06)
        }
    }
}

private extension View {
    func inventoryCardSurface() -> some View {
        modifier(InventoryCardSurfaceModifier())
    }

    func treeRowFrame(id: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TreeRowFramePreferenceKey.self,
                    value: [id: geometry.frame(in: .global)]
                )
            }
        }
    }
}

private struct TreeViewportFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct TreeRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TreeInventoryView: View {
    let store: InventoryStore
    let searchQuery: String
    let categoryName: (String) -> String
    let onAddItemAtLocation: (UUID) -> Void
    let onEditItem: (InventoryItem) -> Void
    let onDeleteItem: (InventoryItem) -> Void
    let onExpandToRowIDs: ([String]) -> Void
    @State private var expandedRowIDs: Set<String> = ["unassigned"]

    var body: some View {
        ForEach(treeRows) { row in
                TreeInventoryRow(
                    row: row,
                    isSearchActive: isShowingSearchResults,
                    searchQuery: searchQuery,
                    categoryName: categoryName,
                    expandedRowIDs: $expandedRowIDs,
                    onAddItemAtLocation: onAddItemAtLocation,
                    onEditItem: onEditItem,
                onDeleteItem: onDeleteItem,
                onExpandToRowIDs: onExpandToRowIDs
            )
            .id(row.id)
        }
        .listRowInsets(InventoryLayout.rowInsets)
        .onAppear(perform: updateExpandedRowsForSearch)
        .onChange(of: searchQuery) { _, _ in
            updateExpandedRowsForSearch()
        }
    }

    private var orphanItems: [InventoryItem] {
        store.items(at: nil)
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingSearchResults: Bool {
        !trimmedSearchQuery.isEmpty
    }

    private var treeRows: [TreeInventoryRowModel] {
        if isShowingSearchResults {
            return filteredTreeRows
        }

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

    private var filteredTreeRows: [TreeInventoryRowModel] {
        var rows = store.rootLocations.compactMap(makeFilteredLocationRow)
        let matchingOrphanItems = orphanItems
            .filter { store.matchesSearch($0, query: trimmedSearchQuery) }
            .map(TreeInventoryRowModel.item)

        if !matchingOrphanItems.isEmpty {
            rows.insert(
                .unassigned(
                    title: String(localized: "inventory.tree.unassigned"),
                    subtitle: String(localized: "inventory.tree.unassigned.subtitle"),
                    count: matchingOrphanItems.count,
                    children: matchingOrphanItems
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
            subtitle: nil,
            count: store.totalItemCount(in: location.id),
            children: childLocations + directItems
        )
    }

    private func makeFilteredLocationRow(_ location: InventoryLocationNode) -> TreeInventoryRowModel? {
        if store.matchesSearch(location, query: trimmedSearchQuery) {
            return makeLocationRow(location)
        }

        let childLocationMatches = store.children(of: location.id).compactMap(makeFilteredLocationRow)
        let matchingDirectItems = store.items(at: location.id)
            .filter { store.matchesSearch($0, query: trimmedSearchQuery) }
            .map(TreeInventoryRowModel.item)
        let matchingItemCount = matchingDirectItems.count + childLocationMatches.reduce(0) { partialResult, row in
            partialResult + row.visibleItemCount
        }

        guard !childLocationMatches.isEmpty || !matchingDirectItems.isEmpty else {
            return nil
        }

        return .location(
            location,
            subtitle: nil,
            count: matchingItemCount,
            children: childLocationMatches + matchingDirectItems
        )
    }

    private func updateExpandedRowsForSearch() {
        expandedRowIDs = isShowingSearchResults ? Set(treeRows.flatMap(\.expandableRowIDs)) : ["unassigned"]
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
    let isSearchActive: Bool
    let searchQuery: String
    let categoryName: (String) -> String
    @Binding var expandedRowIDs: Set<String>
    let onAddItemAtLocation: (UUID) -> Void
    let onEditItem: (InventoryItem) -> Void
    let onDeleteItem: (InventoryItem) -> Void
    let onExpandToRowIDs: ([String]) -> Void

    var body: some View {
        switch row {
        case .location(let location, let subtitle, let count, let children):
            DisclosureGroup(isExpanded: expansionBinding(for: row.id)) {
                ForEach(children) { child in
                    TreeInventoryRow(
                        row: child,
                        isSearchActive: isSearchActive,
                        searchQuery: searchQuery,
                        categoryName: categoryName,
                        expandedRowIDs: $expandedRowIDs,
                        onAddItemAtLocation: onAddItemAtLocation,
                        onEditItem: onEditItem,
                        onDeleteItem: onDeleteItem,
                        onExpandToRowIDs: onExpandToRowIDs
                    )
                    .id(child.id)
                }
            } label: {
                rowLabel(
                    icon: location.parentID == nil ? "door.left.hand.open" : "cabinet.fill",
                    title: makeHighlightedText(
                        for: location.name,
                        matching: searchQuery,
                        baseColor: .primary,
                        dimmedColor: .secondary.opacity(0.72)
                    ),
                    subtitle: subtitle.map {
                        makeHighlightedText(
                            for: $0,
                            matching: searchQuery,
                            baseColor: .secondary,
                            dimmedColor: .secondary.opacity(0.65)
                        )
                    },
                    trailingText: "\(count)"
                )
                .contentShape(Rectangle())
                .treeRowFrame(id: row.id)
                .onTapGesture {
                    toggleExpansion(for: row.id, childRowIDs: children.map(\.id))
                }
                .contextMenu {
                    Button {
                        onAddItemAtLocation(location.id)
                    } label: {
                        Label("inventory.addItem", systemImage: "plus")
                    }
                }
            }
        case .item(let item):
            rowLabel(
                icon: "shippingbox.fill",
                title: makeHighlightedText(
                    for: item.name,
                    matching: searchQuery,
                    baseColor: .primary,
                    dimmedColor: .secondary.opacity(0.72)
                ),
                subtitle: makeHighlightedText(
                    for: categoryName(item.category),
                    matching: searchQuery,
                    baseColor: .secondary,
                    dimmedColor: .secondary.opacity(0.65)
                ),
                trailingText: "x\(item.quantity)"
            )
            .contentShape(Rectangle())
            .treeRowFrame(id: row.id)
            .onTapGesture {
                onEditItem(item)
            }
            .contextMenu {
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
                        isSearchActive: isSearchActive,
                        searchQuery: searchQuery,
                        categoryName: categoryName,
                        expandedRowIDs: $expandedRowIDs,
                        onAddItemAtLocation: onAddItemAtLocation,
                        onEditItem: onEditItem,
                        onDeleteItem: onDeleteItem,
                        onExpandToRowIDs: onExpandToRowIDs
                    )
                    .id(child.id)
                }
            } label: {
                rowLabel(
                    icon: "tray.full.fill",
                    title: makeHighlightedText(
                        for: title,
                        matching: searchQuery,
                        baseColor: .primary,
                        dimmedColor: .secondary.opacity(0.72)
                    ),
                    subtitle: makeHighlightedText(
                        for: subtitle,
                        matching: searchQuery,
                        baseColor: .secondary,
                        dimmedColor: .secondary.opacity(0.65)
                    ),
                    trailingText: "\(count)"
                )
                .contentShape(Rectangle())
                .treeRowFrame(id: row.id)
                .onTapGesture {
                    toggleExpansion(for: row.id, childRowIDs: children.map(\.id))
                }
            }
        }
    }

    private func expansionBinding(for rowID: String) -> Binding<Bool> {
        Binding(
            get: {
                isSearchActive || expandedRowIDs.contains(rowID)
            },
            set: { isExpanded in
                guard !isSearchActive else {
                    return
                }

                if isExpanded {
                    expandedRowIDs.insert(rowID)
                } else {
                    expandedRowIDs.remove(rowID)
                }
            }
        )
    }

    private func toggleExpansion(for rowID: String, childRowIDs: [String] = []) {
        guard !isSearchActive else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedRowIDs.contains(rowID) {
                expandedRowIDs.remove(rowID)
            } else {
                expandedRowIDs.insert(rowID)
                if !childRowIDs.isEmpty {
                    onExpandToRowIDs(childRowIDs)
                }
            }
        }
    }

    private func rowLabel(icon: String, title: AttributedString, subtitle: AttributedString?, trailingText: String) -> some View {
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
                }
            }

            Spacer(minLength: 12)

            Text(trailingText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private func makeHighlightedText(
    for string: String,
    matching query: String,
    baseColor: Color,
    dimmedColor: Color
) -> AttributedString {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    var attributed = AttributedString(string)
    attributed.foregroundColor = baseColor

    guard !trimmedQuery.isEmpty else {
        return attributed
    }

    attributed.foregroundColor = dimmedColor
    var searchStart = string.startIndex
    while searchStart < string.endIndex,
          let matchRange = string.range(
            of: trimmedQuery,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<string.endIndex,
            locale: .current
          ) {
        if let attributedRange = Range(matchRange, in: attributed) {
            attributed[attributedRange].foregroundColor = baseColor
        }

        searchStart = matchRange.upperBound
    }

    return attributed
}

private extension TreeInventoryRowModel {
    var visibleItemCount: Int {
        switch self {
        case .location(_, _, let count, _), .unassigned(_, _, let count, _):
            return count
        case .item:
            return 1
        }
    }

    var expandableRowIDs: [String] {
        guard let children else {
            return []
        }

        return [id] + children.flatMap(\.expandableRowIDs)
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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(itemName)
                        .font(.body)

                    Text(locationLabel)
                        .font(.caption)
                }

                Spacer(minLength: 12)

                VStack {
                    Text("x\(item.quantity)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, InventoryLayout.rowInsets.top)
            .padding(.horizontal, InventoryLayout.rowInsets.leading)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Rectangle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ContentView(authSession: FirebaseAuthSession())
}
