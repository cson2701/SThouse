//
//  ContentView.swift
//  SThouse
//
//  Created by Gavin Song on 13/6/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = InventoryListViewModel()

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

                Section("inventory.section.inventory") {
                    if viewModel.items.isEmpty {
                        ContentUnavailableView(
                            "inventory.empty.title",
                            systemImage: "shippingbox",
                            description: Text("inventory.empty.subtitle")
                        )
                    } else {
                        ForEach(viewModel.items) { item in
                            InventoryRow(item: item) {
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
            .navigationTitle("SThouse")
            .toolbar {
                Button {
                    viewModel.activeSheet = .add
                } label: {
                    Label("inventory.addItem", systemImage: "plus")
                }
            }
            .sheet(item: $viewModel.activeSheet) { sheet in
                switch sheet {
                case .add:
                    AddItemView(mode: .add) { newItem in
                        viewModel.addItem(newItem)
                    }
                case .edit(let item):
                    AddItemView(mode: .edit, onSave: { updatedItem in
                        viewModel.updateItem(updatedItem)
                    }, onDelete: {
                        viewModel.deleteItem(id: item.id)
                    }, item: item)
                }
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

private struct InventoryRow: View {
    let item: InventoryItem
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

                Text("\(localizedCategoryName(for: item.category))  •  \(localizedRoomName(for: item.room))")
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

    private func localizedRoomName(for roomCode: String) -> String {
        InventoryRoom(rawValue: roomCode)?.localizedTitle ?? roomCode
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

private struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AddItemViewModel
    @State private var isShowingDeleteConfirmation = false

    enum Mode {
        case add
        case edit

        var title: LocalizedStringKey {
            switch self {
            case .add:
                return "inventory.addItem"
            case .edit:
                return "inventory.editItem"
            }
        }

        var saveTitle: LocalizedStringKey {
            switch self {
            case .add:
                return "inventory.save"
            case .edit:
                return "inventory.update"
            }
        }
    }

    let mode: Mode
    let onSave: (InventoryItem) -> Void
    let onDelete: (() -> Void)?

    init(mode: Mode, onSave: @escaping (InventoryItem) -> Void, item: InventoryItem? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = nil
        _viewModel = State(initialValue: AddItemViewModel(item: item))
    }

    init(mode: Mode, onSave: @escaping (InventoryItem) -> Void, onDelete: @escaping () -> Void, item: InventoryItem? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        _viewModel = State(initialValue: AddItemViewModel(item: item))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("inventory.section.item") {
                    TextField("inventory.field.name", text: binding(\.name))
                    Picker("inventory.field.room", selection: binding(\.room)) {
                        Text(InventoryRoom.unspecified.localizedTitle).tag(InventoryRoom.unspecified)
                        ForEach(InventoryRoom.allCases) { room in
                            if room != .unspecified {
                            Text(room.localizedTitle).tag(room)
                            }
                        }
                    }
                    Picker("inventory.field.category", selection: binding(\.category)) {
                        Text(InventoryCategory.unspecified.localizedTitle).tag(InventoryCategory.unspecified)
                        ForEach(InventoryCategory.allCases) { category in
                            if category != .unspecified {
                            Text(category.localizedTitle).tag(category)
                            }
                        }
                    }
                    Stepper {
                        Text("\(String(localized: "inventory.field.quantity")): \(viewModel.quantity)")
                    } onIncrement: {
                        incrementQuantity()
                    } onDecrement: {
                        decrementQuantity()
                    }
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("inventory.cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.saveTitle) {
                        onSave(viewModel.makeItem())
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                }

                if mode == .edit {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("inventory.delete", systemImage: "trash")
                        }
                    }
                }
            }
            .alert(
                "inventory.delete.confirmation.title",
                isPresented: $isShowingDeleteConfirmation,
                presenting: viewModel.name
            ) { itemName in
                Button("inventory.delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }

                Button("inventory.cancel", role: .cancel) {}
            } message: { itemName in
                Text(verbatim: String(format: String(localized: "inventory.delete.confirmation.message"), itemName))
            }
        }
    }

    private func incrementQuantity() {
        guard viewModel.quantity < 999 else {
            return
        }

        viewModel.quantity += 1
    }

    private func decrementQuantity() {
        if viewModel.quantity > 1 {
            viewModel.quantity -= 1
            return
        }

        guard mode == .edit else {
            return
        }

        isShowingDeleteConfirmation = true
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AddItemViewModel, T>) -> Binding<T> {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }
}

#Preview {
    ContentView()
}
