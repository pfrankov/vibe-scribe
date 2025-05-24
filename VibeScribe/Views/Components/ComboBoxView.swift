//
//  ComboBoxView.swift
//  VibeScribe
//
//  Created by System on 16.04.2025.
//

import SwiftUI
import AppKit

/// Нативный macOS PopUpButton, обернутый в SwiftUI
struct ComboBoxView: NSViewRepresentable {
    var placeholder: String
    var options: [String]
    @Binding var selectedOption: String
    
    func makeNSView(context: Context) -> NSPopUpButton {
        let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        popUpButton.target = context.coordinator
        popUpButton.action = #selector(Coordinator.selectionChanged(_:))
        
        // Добавляем опцию для ввода своего значения
        popUpButton.menu?.addItem(NSMenuItem.separator())
        
        let customItem = NSMenuItem(title: "Custom...", action: nil, keyEquivalent: "")
        customItem.tag = -1
        customItem.target = context.coordinator
        customItem.action = #selector(Coordinator.customOptionSelected(_:))
        popUpButton.menu?.addItem(customItem)
        
        return popUpButton
    }
    
    func updateNSView(_ nsView: NSPopUpButton, context: Context) {
        // Обновляем список опций
        nsView.removeAllItems()
        
        for option in options {
            nsView.addItem(withTitle: option)
        }
        
        // Добавляем опцию для ввода своего значения
        nsView.menu?.addItem(NSMenuItem.separator())
        
        let customItem = NSMenuItem(title: "Custom...", action: nil, keyEquivalent: "")
        customItem.tag = -1
        customItem.target = context.coordinator
        customItem.action = #selector(Coordinator.customOptionSelected(_:))
        nsView.menu?.addItem(customItem)
        
        // Если выбранное значение есть в списке, выбираем его
        if let index = options.firstIndex(of: selectedOption) {
            nsView.selectItem(at: index)
        } else if !selectedOption.isEmpty {
            // Если значение не в списке, но не пустое, добавляем его временно и выбираем
            nsView.insertItem(withTitle: selectedOption, at: 0)
            nsView.selectItem(at: 0)
        } else if !placeholder.isEmpty {
            // Если значение пустое, но есть плейсхолдер, используем его
            nsView.insertItem(withTitle: placeholder, at: 0)
            nsView.selectItem(at: 0)
            nsView.item(at: 0)?.isEnabled = false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: ComboBoxView
        
        init(_ parent: ComboBoxView) {
            self.parent = parent
        }
        
        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let selectedTitle = sender.selectedItem?.title else { return }
            
            // Не меняем значение, если выбран плейсхолдер
            if selectedTitle == parent.placeholder {
                return
            }
            
            parent.selectedOption = selectedTitle
        }
        
        @objc func customOptionSelected(_ sender: NSMenuItem) {
            // Создаем диалоговое окно для ввода значения
            let alert = NSAlert()
            alert.messageText = "Enter custom value"
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            textField.stringValue = parent.selectedOption
            textField.placeholderString = "Enter value..."
            
            alert.accessoryView = textField
            
            // Показываем диалог и обрабатываем результат
            if alert.runModal() == .alertFirstButtonReturn {
                let customValue = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !customValue.isEmpty {
                    parent.selectedOption = customValue
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var selected = "option1"
    
    return VStack(spacing: 20) {
        ComboBoxView(
            placeholder: "Select an option",
            options: ["option1", "option2", "option3", "A really long option that should be truncated"],
            selectedOption: $selected
        )
        .frame(width: 300)
        
        Text("Selected: \(selected)")
    }
    .padding()
} 