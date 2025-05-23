//
//  SettingsView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData

// MARK: - UI Constants
private struct UIConstants {
    // Base spacing units
    static let baseSpacing: CGFloat = 4.0
    
    // Spacing multipliers
    static let spacing1x: CGFloat = baseSpacing * 1 // 4pt
    static let spacing2x: CGFloat = baseSpacing * 2 // 8pt
    static let spacing3x: CGFloat = baseSpacing * 3 // 12pt
    static let spacing4x: CGFloat = baseSpacing * 4 // 16pt
    static let spacing5x: CGFloat = baseSpacing * 5 // 20pt
    static let spacing6x: CGFloat = baseSpacing * 6 // 24pt
    static let spacing8x: CGFloat = baseSpacing * 8 // 32pt
    
    // Интервалы для групп
    static let blockInternalSpacing: CGFloat = 8 // Стандартный macOS интервал для элементов в группе
    
    // Интервалы между блоками
    static let blockExternalSpacing: CGFloat = 20 // Стандартный macOS интервал между группами
    
    // Padding
    static let sectionPadding = spacing5x // 20pt
    static let blockPadding = 16.0 // Стандартный macOS отступ для групп
    static let formElementPadding = 8.0 // Стандартный отступ для полей ввода
    static let tabViewTopPadding = 16.0 // Уменьшенный отступ сверху для компактности
    static let tabPickerHorizontalPadding = 20.0 // macOS стандарт
    
    // Margins
    static let horizontalMargin = 24.0 // Увеличенный отступ по горизонтали 
    static let verticalMargin = 16.0 // Стандартный отступ по вертикали
    
    // Corner radius
    static let cornerRadius: CGFloat = 6.0 // Стандартный macOS радиус
    static let formElementRadius: CGFloat = 4.0 // Стандартный macOS радиус для полей
    
    // Input fields
    static let textFieldHeight: CGFloat = 28.0 // Стандартная высота поля ввода
    static let textEditorHeight: CGFloat = 100.0 // Уменьшенная высота для текстовых блоков
    
    // Border width
    static let borderWidth: CGFloat = 0.5 // Более тонкие границы
    
    // Content width
    static let tabPickerMaxWidth: CGFloat = 280.0 // Уменьшенная ширина селектора для компактности
    
    // Colors
    static let blockBackgroundColor = Color(NSColor.controlBackgroundColor) // Стандартный цвет фона macOS
    
    // Typography
    struct FontSize {
        static let title: CGFloat = 13.0      // Стандартный macOS размер для заголовков
        static let subtitle: CGFloat = 13.0   // Стандартный macOS размер
        static let body: CGFloat = 13.0       // Стандартный macOS размер
        static let caption: CGFloat = 11.0    // Стандартный macOS размер для caption
    }
    
    struct FontWeight {
        static let title = Font.Weight.medium // Средняя толщина для заголовков
        static let subtitle = Font.Weight.regular
        static let body = Font.Weight.regular
        static let caption = Font.Weight.regular
    }
    
    // Adjusted spacing for better grouping
    static let betweenRelatedElements = 4.0 // Минимальный интервал
    static let betweenDescriptionAndField = 6.0 // Малый интервал
    static let betweenFieldAndHint = 6.0 // Малый интервал
    static let betweenElementGroups = 16.0 // Стандартный интервал между группами
    static let betweenMajorSections = 24.0 // Больший интервал между основными секциями
    
    // Section spacing
    static let sectionSpacing = 20.0 // Стандартный интервал для секций
}

// MARK: - Typography System
private struct Typography {
    static let title = Font.system(size: UIConstants.FontSize.title, weight: UIConstants.FontWeight.title)
    static let subtitle = Font.system(size: UIConstants.FontSize.subtitle, weight: UIConstants.FontWeight.subtitle)
    static let body = Font.system(size: UIConstants.FontSize.body, weight: UIConstants.FontWeight.body)
    static let caption = Font.system(size: UIConstants.FontSize.caption, weight: UIConstants.FontWeight.caption)
}

// Proper settings view with segmented control
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<AppSettings> { $0.id == "app_settings" })
    private var appSettings: [AppSettings]
    
    @Environment(\.colorScheme) var colorScheme // Для определения темы
    @FocusState private var isTextFieldFocused: Bool // Общий фокус для всех TextField
    @FocusState private var isTextEditorFocused: Bool // Общий фокус для всех TextEditor
    
    // Alert state
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    // Computed property to get or create settings
    private var settings: AppSettings {
        if let existingSettings = appSettings.first {
            return existingSettings
        } else {
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            return newSettings
        }
    }
    
    @State private var selectedTab: SettingsTab = .speechToText
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Settings", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.rawValue)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, UIConstants.tabPickerHorizontalPadding)
            .padding(.top, UIConstants.tabViewTopPadding)
            .padding(.bottom, UIConstants.spacing4x)
            .frame(maxWidth: UIConstants.tabPickerMaxWidth)
            
            // Content based on selected tab
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.betweenMajorSections) {
                    VStack(alignment: .leading, spacing: UIConstants.betweenMajorSections) {
                        if selectedTab == .speechToText {
                            // Speech to Text Tab Content
                            contentBlock {
                                Text("Whisper compatible API URL")
                                    .font(Typography.body)
                                styledTextField("https://api.example.com/v1/audio/transcriptions", value: Binding(
                                    get: { settings.whisperURL },
                                    set: { settings.whisperURL = $0; trySave() }
                                ))
                                captionText("e.g., https://api.openai.com/v1/audio/transcriptions or your local Whisper instance.")
                            }
                            
                            // Whisper API Key
                            contentBlock {
                                Text("Whisper API Key")
                                    .font(Typography.body)
                                styledTextField("sk-...", value: Binding(
                                    get: { settings.whisperAPIKey },
                                    set: { settings.whisperAPIKey = $0; trySave() }
                                ))
                                captionText("Your Whisper API key. Leave empty for local servers that don't require authentication.")
                            }
                            
                            // Whisper Model selection
                            contentBlock {
                                Text("Whisper Model")
                                    .font(Typography.body)
                                ComboBoxView(
                                    placeholder: "Select Whisper model",
                                    options: ["whisper-1", "tiny", "base", "small", "medium", "large", "large-v1", "large-v2", "large-v3"],
                                    selectedOption: Binding(
                                        get: { settings.whisperModel },
                                        set: { settings.whisperModel = $0; trySave() }
                                    )
                                )
                                .frame(height: 22)
                                captionText("Specify the Whisper model to use for transcription. May vary depending on your server implementation.")
                            }
                        } else if selectedTab == .summary {
                            // Summary Tab Content
                            // LLM API section
                            contentBlock {
                                Text("OpenAI compatible API URL")
                                    .font(Typography.body)
                                styledTextField("https://api.example.com/v1/chat/completions", value: Binding(
                                    get: { settings.openAICompatibleURL },
                                    set: { settings.openAICompatibleURL = $0; trySave() }
                                ))
                                captionText("e.g., https://api.openai.com/v1/chat/completions or your custom summarization endpoint.")
                            }
                            
                            // OpenAI API Key
                            contentBlock {
                                Text("OpenAI API Key")
                                    .font(Typography.body)
                                styledTextField("sk-...", value: Binding(
                                    get: { settings.openAIAPIKey },
                                    set: { settings.openAIAPIKey = $0; trySave() }
                                ))
                                captionText("Your OpenAI API key. Leave empty for local servers that don't require authentication.")
                            }
                            
                            // OpenAI Model selection
                            contentBlock {
                                Text("OpenAI Model")
                                    .font(Typography.body)
                                ComboBoxView(
                                    placeholder: "Select LLM model",
                                    options: ["gpt-3.5-turbo", "gpt-4", "gpt-4-turbo", "claude-3-opus-20240229"],
                                    selectedOption: Binding(
                                        get: { settings.openAIModel },
                                        set: { settings.openAIModel = $0; trySave() }
                                    )
                                )
                                .frame(height: 22)
                                captionText("Specify the model to use for summarization. Custom models from local servers can be entered manually.")
                            }
                            
                            // Chunk Processing Prompt
                            contentBlock {
                                Text("Prompt for individual transcription chunks")
                                    .font(Typography.body)
                                styledTextEditor(Binding(
                                    get: { settings.chunkPrompt },
                                    set: { settings.chunkPrompt = $0; trySave() }
                                ))
                                captionText("Use {transcription} as a placeholder for the transcription text.")
                            }
                            
                            // Final Summary Prompt
                            contentBlock {
                                Text("Prompt for combining chunk summaries")
                                    .font(Typography.body)
                                styledTextEditor(Binding(
                                    get: { settings.summaryPrompt },
                                    set: { settings.summaryPrompt = $0; trySave() }
                                ))
                                captionText("Use {summaries} as a placeholder for the combined chunk summaries.")
                            }
                            
                            // Chunk Size Settings
                            contentBlock {
                                Text("Chunk Size (characters)")
                                    .font(Typography.body)
                                styledTextField("1000", value: Binding(
                                    get: { settings.chunkSize },
                                    set: { newValue in 
                                        let clampedValue = max(100, min(2000, newValue))
                                        if settings.chunkSize != clampedValue {
                                            settings.chunkSize = clampedValue
                                            trySave()
                                        }
                                    }
                                ), format: .number)
                                captionText("Text chunk size for LLM processing (100-2000 characters). Larger chunks = more context but higher token cost.")
                            }
                        }
                        
                        Spacer(minLength: UIConstants.spacing5x) // Отступ снизу
                    }
                    .padding(.vertical, UIConstants.verticalMargin) // Оставляем только вертикальные отступы для этого блока
                    .frame(maxWidth: .infinity) // Контент занимает всю доступную ширину
                }
                .frame(maxWidth: .infinity) // Главный VStack занимает всю ширину ScrollView
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, UIConstants.horizontalMargin)
        .onAppear {
            _ = settings
        }
    }
    
    // MARK: - Helper Functions
    
    private func trySave() {
        do {
            try modelContext.save()
        } catch {
            print("Error saving settings: \(error)")
        }
    }
    
    // MARK: - UI Components
    
    // Clean section header - заменяем на contentBlock
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: UIConstants.spacing3x) {
            Image(systemName: icon)
                .font(.system(size: 16))
            
            Text(title)
                .font(Typography.title)
        }
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, UIConstants.spacing4x)
    }
    
    // Shared styling for content block - теперь это просто секция БЕЗ заголовка
    private func contentBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.betweenRelatedElements) { // Более плотные отступы для связанных элементов
            content()
        }
        // Убираем фон и рамку отсюда, они теперь у конкретных элементов если нужны
    }
    
    // Shared styling for TextField
    private func styledTextField<T>(_ placeholder: String, value: Binding<T>, format: Format = .text) -> some View where T: LosslessStringConvertible {
        Group {
            if let textValue = value as? Binding<String> {
                TextField(placeholder, text: textValue)
                    .font(.system(size: 13))
                    .controlSize(.regular)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(UIConstants.formElementRadius)
                    .focused($isTextFieldFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.formElementRadius)
                            .stroke(
                                isTextFieldFocused ? Color(NSColor.controlAccentColor) : Color(NSColor.separatorColor),
                                lineWidth: 0.5
                            )
                    )
                    .frame(maxWidth: .infinity)
            } else if format == .number, let intValue = value as? Binding<Int> {
                TextField(placeholder, value: intValue, format: .number)
                    .font(.system(size: 13))
                    .controlSize(.regular)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(UIConstants.formElementRadius)
                    .focused($isTextFieldFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.formElementRadius)
                            .stroke(
                                isTextFieldFocused ? Color(NSColor.controlAccentColor) : Color(NSColor.separatorColor),
                                lineWidth: 0.5
                            )
                    )
                    .frame(width: 100)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private enum Format {
        case text, number
    }
    
    // Shared styling for TextEditor
    private func styledTextEditor(_ text: Binding<String>) -> some View {
        TextEditor(text: text)
            .font(.system(size: 13))
            .padding(UIConstants.spacing2x)
            .frame(height: UIConstants.textEditorHeight)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(UIConstants.formElementRadius)
            .focused($isTextEditorFocused)
            .overlay( 
                RoundedRectangle(cornerRadius: UIConstants.formElementRadius)
                    .stroke(
                        isTextEditorFocused ? Color(NSColor.controlAccentColor) : Color(NSColor.separatorColor),
                        lineWidth: 0.5
                    )
            )
            .frame(maxWidth: .infinity)
    }
    
    // Shared styling for caption text
    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
    }
}

// MARK: - Preview
#Preview {
    SettingsView()
        .modelContainer(for: AppSettings.self, inMemory: true)
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case speechToText = "Speech to Text"
    case summary = "Summary"
    
    var id: String { self.rawValue }
} 