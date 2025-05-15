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
    var activeColor: Color = Color(NSColor.controlAccentColor)
    var inactiveColor: Color = Color(NSColor.unemphasizedSelectedContentBackgroundColor)
    var isActive: Bool = true
    
    var body: some View {
        HStack(spacing: 3) { // Уменьшенный интервал для компактности
            ForEach(0..<min(levels.count, 28), id: \.self) { index in // Ограничиваем количество полос
                Capsule() // Используем Capsule для закругленных краев
                    .fill(isActive 
                          ? activeColor.opacity(max(0.3, Double(levels[index]))) // Динамическая непрозрачность
                          : inactiveColor)
                    .frame(width: 3, height: CGFloat(levels[index] * 50) + 3) // Более тонкие полоски
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: levels[index]) // Более естественная анимация
            }
        }
        .frame(height: 60) // Высота чуть меньше для компактности
        .padding(.vertical, 10)
        .padding(.horizontal, 5)
    }
} 