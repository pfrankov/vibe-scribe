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
                .fontWeight(isSelected ? .semibold : .regular) // Highlight selected
                .frame(maxWidth: .infinity) // Make button take available width
                .padding(.vertical, 8) // Vertical padding inside button
                .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear) // Subtle background for selected
                .contentShape(Rectangle()) // Ensure whole area is tappable
        }
        .buttonStyle(PlainButtonStyle()) // Remove default button chrome
        .foregroundColor(isSelected ? .accentColor : .primary) // Text color change
        .cornerRadius(6) // Slightly rounded corners for the background
        .animation(.easeInOut(duration: 0.15), value: isSelected) // Animate selection change
    }
} 