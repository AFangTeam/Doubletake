//
//  Item.swift
//  Timeline
//
//  Created by Eric on 2026/5/17.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
