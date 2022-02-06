//
//  JSON.swift
//  MonadicJSON macOS
//
//  Created by Charlotte Tortorella on 18/4/19.
//

import Foundation

public indirect enum JSON: Equatable {
    case null
    case string(String)
    case number(String)
    case bool(Bool)
    case dictionary([String: JSON])
    case array([JSON])
}
