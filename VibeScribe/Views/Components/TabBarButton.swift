//
//  TabBarButton.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI

// --- Helper View for Tab Bar Button ---
struct TabBarButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color(NSColor.selectedContentBackgroundColor).opacity(0.3) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(isSelected ? Color(NSColor.labelColor) : Color(NSColor.secondaryLabelColor))
        .cornerRadius(6)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
} 