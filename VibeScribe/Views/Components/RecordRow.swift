//
//  RecordRow.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData

// View for a single row in the records list
struct RecordRow: View {
    // Use @Bindable for direct modification of @Model
    @Bindable var record: Record 

    @State private var isEditing: Bool = false
    @State private var editingName: String = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { // Уменьшаем спейсинг до 4pt
                // ZStack to overlay TextField on Text for editing
                ZStack(alignment: .leading) {
                    // --- TextField (Visible when editing) ---
                    TextField("Name", text: $editingName)
                        .textFieldStyle(.plain) // Стандартный плоский стиль
                        .focused($isNameFieldFocused)
                        .onSubmit { // Handle Enter key press
                            saveName()
                        }
                        // Prevent clicks on TextField from selecting the row
                        .onTapGesture {}
                        // Apply same font/padding as Text for alignment
                        .font(.headline) // Стандартный headline
                        // Make TextField visible only when editing
                        .opacity(isEditing ? 1 : 0)
                        .disabled(!isEditing) // Disable when not editing

                    // --- Text (Visible when not editing) ---
                    Text(record.name)
                        .font(.headline) // Стандартный headline
                        .lineLimit(1) // Ограничиваем одной строкой
                        // Make Text visible only when *not* editing
                        .opacity(isEditing ? 0 : 1)
                        // Double-click to start editing
                        .onTapGesture(count: 2) {
                            startEditing()
                        }
                }

                HStack(spacing: 4) { // Уменьшенный интервал для деталей
                    Text(record.date, style: .date)
                        .foregroundColor(Color(NSColor.secondaryLabelColor)) // Используем системный цвет вместо ручной настройки opacity
                    Text("•") // Bullet разделитель вместо дефиса
                        .foregroundColor(Color(NSColor.secondaryLabelColor)) // Используем системный цвет
                    Text(formatDuration(record.duration))
                        .foregroundColor(Color(NSColor.secondaryLabelColor)) // Используем системный цвет
                }
                .font(.caption) // Стандартный caption для macOS
            }
            Spacer()
            
            // Индикатор раскрытия
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color(NSColor.secondaryLabelColor)) // Системный цвет для chevron
        }
        .padding(.vertical, 8) // Увеличиваем отступ для лучшей читаемости
        .padding(.horizontal, 4) // Добавляем небольшой горизонтальный отступ
        .cornerRadius(4) // Небольшое скругление для строки
        // Detect when the text field loses focus to cancel editing
        .onChange(of: isNameFieldFocused) { oldValue, newValue in
            if !newValue && isEditing { // If focus is lost AND we were editing
                // This handles clicking away or pressing Esc (which also removes focus)
                cancelEditing()
            }
        }
    }

    private func startEditing() {
        editingName = record.name // Initialize TextField with current name
        isEditing = true
        // Delay focus slightly to ensure TextField is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
             isNameFieldFocused = true
        }
        print("Started editing record: \(record.name)")
    }

    private func saveName() {
        // Only save if the name is valid and actually changed
        if !editingName.isEmpty && editingName != record.name {
            print("Saving new name: \(editingName) for record ID: \(record.id)")
            record.name = editingName
            // SwiftData @Bindable should handle the save automatically
        } else {
            print("Name unchanged or empty, reverting.")
        }
        isEditing = false // Exit editing mode
        isNameFieldFocused = false // Ensure focus is released
    }

    private func cancelEditing() {
        print("Cancelled editing for record: \(record.name)")
        isEditing = false // Exit editing mode
        isNameFieldFocused = false // Ensure focus is released
        // No need to reset editingName, it will be re-initialized on next edit
    }
} 