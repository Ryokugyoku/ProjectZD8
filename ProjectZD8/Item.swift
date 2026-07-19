//
//  Item.swift
//  ProjectZD8
//
//  Created by Maeda Mitsuhiro on 2026/07/19.
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
