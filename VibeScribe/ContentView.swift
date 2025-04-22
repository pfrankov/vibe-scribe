//
//  ContentView.swift
//  VibeScribe
//
//  Created by Frankov Pavel on 13.04.2025.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack {
                Picker("", selection: $selectedTab) {
                    Text("Records").tag(0)
                    Text("Settings").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
            }
            
            Divider()
            
            // Tab content
            TabView(selection: $selectedTab) {
                // Records Tab
                VStack {
                    List {
                        Text("Record item 1")
                        Text("Record item 2")
                        Text("Record item 3")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag(0)
                
                // Settings Tab
                VStack {
                    Text("Settings content would go here")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .tag(1)
            }
            .tabViewStyle(DefaultTabViewStyle())
            
            Divider()
            
            // Quit button
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .padding()
            }
        }
    }
}

#Preview {
    ContentView()
}
