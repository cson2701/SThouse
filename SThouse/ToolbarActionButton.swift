//
//  ToolbarActionButton.swift
//  SThouse
//
//  Created by Codex on 14/6/2026.
//

import SwiftUI

struct ToolbarActionButton: View {
    enum Style {
        case plain
        case prominentBlue
    }

    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    let style: Style
    let role: ButtonRole?
    let action: () -> Void

    init(
        systemImage: String,
        accessibilityLabel: LocalizedStringKey,
        style: Style = .plain,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.style = style
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .toolbarActionStyle(style)
    }
}

private extension View {
    @ViewBuilder
    func toolbarActionStyle(_ style: ToolbarActionButton.Style) -> some View {
        switch style {
        case .plain:
            buttonStyle(.plain)
        case .prominentBlue:
            buttonStyle(.borderedProminent)
                .tint(.blue)
        }
    }
}
