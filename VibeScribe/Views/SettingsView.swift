//
//  SettingsView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI

// Separate view for Settings
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 15) { // Added spacing
            Spacer() // Push content to center
            Image(systemName: "gear.circle") // Placeholder Icon
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("Settings")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Application settings will be available here.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer() // Push content to center
        }
        .padding() // Add padding to the content
        // Ensure SettingsView fills the space
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
} 