//
//  CategorySelectionView.swift
//  SThouse
//
//  Created by Codex on 5/7/2026.
//

import SwiftUI

struct CategorySelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let store: InventoryStore
    @Binding var selectedCategoryID: String?

    @State private var isShowingManagement = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.sortedCategories) { category in
                    Button {
                        selectedCategoryID = category.id
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(category.name)
                                .foregroundStyle(.primary)

                            Spacer(minLength: 12)

                            if selectedCategoryID == category.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("inventory.category.select")
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
                    ToolbarActionButton(
                        systemImage: "slider.horizontal.3",
                        accessibilityLabel: "inventory.category.manage"
                    ) {
                        isShowingManagement = true
                    }
                }
            }
            .sheet(isPresented: $isShowingManagement) {
                CategoryManagementView(store: store)
            }
        }
    }
}

struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    let store: InventoryStore

    @State private var editorTarget: CategoryEditorTarget?
    @State private var deleteTarget: InventoryCategory?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                if store.sortedCategories.isEmpty {
                    ContentUnavailableView(
                        "inventory.category.manage.empty.title",
                        systemImage: "tag",
                        description: Text("inventory.category.manage.empty.subtitle")
                    )
                } else {
                    ForEach(store.sortedCategories) { category in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.name)
                                    .font(.body.weight(.medium))

                                if category.id == store.defaultCategoryID {
                                    Text("inventory.category.default")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 12)

                            Menu {
                                if category.id != store.defaultCategoryID {
                                    Button("inventory.category.rename") {
                                        editorTarget = .rename(category: category)
                                    }
                                }

                                if category.id != store.defaultCategoryID {
                                    Button("inventory.delete", role: .destructive) {
                                        deleteTarget = category
                                        isShowingDeleteConfirmation = true
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("inventory.category.manage")
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
                        editorTarget = .add
                    } label: {
                        Label("inventory.category.add", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                CategoryEditorSheet(store: store, target: target)
            }
            .alert(
                "inventory.category.delete.title",
                isPresented: $isShowingDeleteConfirmation,
                presenting: deleteTarget
            ) { category in
                Button("inventory.delete", role: .destructive) {
                    store.deleteCategory(id: category.id)
                }

                Button("inventory.cancel", role: .cancel) {}
            } message: { _ in
                Text("inventory.category.delete.message")
            }
        }
    }
}

private struct CategoryEditorTarget: Identifiable {
    enum Mode {
        case add
        case rename(InventoryCategory)
    }

    let id = UUID()
    let mode: Mode

    static let add = CategoryEditorTarget(mode: .add)

    static func rename(category: InventoryCategory) -> CategoryEditorTarget {
        CategoryEditorTarget(mode: .rename(category))
    }
}

private struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let store: InventoryStore
    let target: CategoryEditorTarget

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("inventory.category.name", text: $name)
                } footer: {
                    if case .rename(let category) = target.mode {
                        Text(String(format: String(localized: "inventory.category.rename.footer"), category.name))
                    }
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(title)
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
            if case .rename(let category) = target.mode {
                name = category.name
            }
        }
    }

    private var title: LocalizedStringKey {
        switch target.mode {
        case .add:
            "inventory.category.add"
        case .rename:
            "inventory.category.rename"
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        switch target.mode {
        case .add:
            _ = store.ensureCategory(named: trimmedName)
        case .rename(let category):
            store.renameCategory(id: category.id, name: trimmedName)
        }

        dismiss()
    }
}
