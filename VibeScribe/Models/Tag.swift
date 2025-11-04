//
//  Tag.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 15.04.2025.
//

import Foundation
import SwiftData

@Model
final class Tag: Identifiable {
    var id: UUID
    @Attribute(.unique) var name: String
    var records: [Record]

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.records = []
    }
}
