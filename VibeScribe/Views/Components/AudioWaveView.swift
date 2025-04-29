//
//  AudioWaveView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI

// --- Audio Wave Visualization --- 
struct AudioWaveView: View {
    var levels: [Float]
    var activeColor: Color = .red
    var inactiveColor: Color = .secondary
    var isActive: Bool = true
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<levels.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(isActive ? activeColor : inactiveColor)
                    .frame(width: 8, height: CGFloat(levels[index] * 60) + 5) // Min height of 5, max of 65
                    .animation(.easeOut(duration: 0.2), value: levels[index])
            }
        }
        .frame(height: 65) // Match the height used by the mic icon
        .padding()
    }
} 