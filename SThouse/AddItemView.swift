//
//  AddItemView.swift
//  SThouse
//
//  Created by Codex on 13/6/2026.
//

import SwiftUI

struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AddItemViewModel
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingLocationPicker = false

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
    let store: InventoryStore
    let onSave: (InventoryItem) -> Void
    let onDelete: (() -> Void)?

    init(mode: Mode, store: InventoryStore, onSave: @escaping (InventoryItem) -> Void, item: InventoryItem? = nil) {
        self.mode = mode
        self.store = store
        self.onSave = onSave
        self.onDelete = nil
        _viewModel = State(initialValue: AddItemViewModel(item: item))
    }

    init(mode: Mode, store: InventoryStore, onSave: @escaping (InventoryItem) -> Void, onDelete: @escaping () -> Void, item: InventoryItem? = nil) {
        self.mode = mode
        self.store = store
        self.onSave = onSave
        self.onDelete = onDelete
        _viewModel = State(initialValue: AddItemViewModel(item: item))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("inventory.section.item") {
                    TextField("inventory.field.name", text: binding(\.name))

                    Button {
                        isShowingLocationPicker = true
                    } label: {
                        HStack {
                            Text("inventory.field.location")
                            Spacer()

                            Text(locationLabel)
                                .foregroundStyle(viewModel.selectedLocationID == nil ? .secondary : .primary)
                                .multilineTextAlignment(.trailing)
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

                if mode == .edit {
                    Text("\(String(localized: "inventory.field.lastEditedBy")): \(lastEditedByLabel)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)                }
            }
            .navigationTitle(mode.title)
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
                        accessibilityLabel: mode.saveTitle,
                        style: .prominentBlue
                    ) {
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
            .sheet(isPresented: $isShowingLocationPicker) {
                LocationSelectionView(store: store, selectedLocationID: binding(\.selectedLocationID))
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

                Button("inventory.cancel", role: .cancel) { }
            } message: { itemName in
                Text(verbatim: String(format: String(localized: "inventory.delete.confirmation.message"), itemName))
            }
        }
    }

    private var locationLabel: String {
        if let selectedLocationID = viewModel.selectedLocationID {
            return store.locationPathDescription(for: selectedLocationID)
        }

        return String(localized: "inventory.location.select")
    }

    private var lastEditedByLabel: String {
        guard let lastEditedBy = viewModel.lastEditedBy, !lastEditedBy.isEmpty else {
            return String(localized: "inventory.lastEditedBy.unknown")
        }

        return lastEditedBy
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
