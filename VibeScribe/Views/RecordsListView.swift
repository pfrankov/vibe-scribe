//
//  RecordsListView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData

// Separate view for the list of records
struct RecordsListView: View {
    // Use the actual Record model type
    let records: [Record]
    @Binding var selectedRecord: Record?
    @Binding var showRecordingSheet: Bool
    var onDelete: (Record) -> Void

    var body: some View {
        VStack(spacing: 0) { // Убираем пространство между элементами
            // Header with New Recording Button
            HStack(alignment: .center) { // Выравнивание по центру для лучшего вида
                Text("All Recordings")
                    .font(.title3) // Более подходящий размер для заголовка секции
                    .fontWeight(.semibold) // Чуть более выразительный
                    .foregroundColor(.primary) // Гарантированно основной цвет для максимального контраста
                Spacer()
                Button {
                    showRecordingSheet = true
                } label: {
                    Label("New Recording", systemImage: "plus.circle.fill") // Используем plus.circle.fill для большей заметности
                        .font(.body)
                }
                .buttonStyle(.borderless) // Используем системный стиль без явной окраски
                .controlSize(.regular) // Стандартный размер
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12) // Одинаковые отступы сверху и снизу
            .background(Color(NSColor.windowBackgroundColor)) // Стандартный фон окна

            // Use a Group to switch between List and Empty State
            Group {
                if records.isEmpty {
                    VStack(spacing: 12) { // Добавлен стандартный интервал
                        Spacer() // Pushes content to center
                        Image(systemName: "waveform.slash")  // Более подходящая SF Symbol
                            .font(.system(size: 40)) // Стандартный размер иконки
                            .foregroundColor(Color(NSColor.secondaryLabelColor)) // Системный цвет
                            .padding(.bottom, 4)
                        Text("No recordings yet")
                            .font(.headline)
                            .foregroundColor(Color(NSColor.labelColor)) // Системный цвет вместо .primary.opacity()
                        Text("Click + to create your first recording") // Более простая инструкция
                            .font(.subheadline)
                            .foregroundColor(Color(NSColor.secondaryLabelColor)) // Системный цвет
                        Spacer() // Pushes content to center
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure VStack fills space
                } else {
                    List {
                        // Iterate over the fetched records
                        ForEach(records) { record in
                            RecordRow(record: record)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedRecord = record // Set the selected record to show the detail sheet
                                }
                                // Updated Context Menu
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onDelete(record) // Call the delete closure
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .listRowBackground(Color(NSColor.alternatingContentBackgroundColors[records.firstIndex(of: record)! % 2])) // Чёткое чередование фона
                                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)) // Стандартные macOS отступы для строк
                        }
                    }
                    .listStyle(.plain) // Используем plain вместо inset для более чёткого разделения
                    .background(Color(NSColor.windowBackgroundColor)) // Корректный фон окна
                    .cornerRadius(6) // Легкое скругление углов списка
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5) // Системный цвет для разделителей
                    )
                    .padding(.horizontal, 8) // Отступы по бокам для рамки
                }
            }
        }
    }
} 