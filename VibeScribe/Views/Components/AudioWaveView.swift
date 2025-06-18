//
//  AudioWaveView.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import SwiftUI

// --- Audio Wave Visualization --- 
struct AudioWaveView: View {
    var levels: [Float]
    var activeColor: Color = Color(NSColor.controlAccentColor)
    var inactiveColor: Color = Color(NSColor.unemphasizedSelectedContentBackgroundColor)
    var isActive: Bool = true
    
    var body: some View {
        HStack(spacing: 3) { // Reduced spacing for compactness
            ForEach(0..<min(levels.count, 28), id: \.self) { index in // Limit number of bars
                Capsule() // Use Capsule for rounded edges
                    .fill(isActive 
                          ? activeColor.opacity(max(0.3, Double(levels[index]))) // Dynamic opacity
                          : inactiveColor)
                    .frame(width: 3, height: CGFloat(levels[index] * 50) + 3) // Thinner bars
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: levels[index]) // More natural animation
            }
        }
        .frame(height: 60) // Slightly smaller height for compactness
        .padding(.vertical, 10)
        .padding(.horizontal, 5)
    }
} 