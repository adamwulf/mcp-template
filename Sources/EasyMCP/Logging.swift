//
//  Logging.swift
//  mcp-template
//
//  Created by Adam Wulf on 3/11/25.
//

import Logging

extension Logger {
    /// Helper function for structured logging in logfmt format
    func logfmt(_ level: Logger.Level, _ pairs: [String: Any]) {
        let message = pairs.map { key, value in
            if let stringValue = value as? String, stringValue.contains(" ") {
                return "\(key)=\"\(stringValue)\""
            } else {
                return "\(key)=\(value)"
            }
        }.joined(separator: " ")

        // Log using the SwiftLog logger
        switch level {
        case .trace: trace("\(message)")
        case .debug: debug("\(message)")
        case .info: info("\(message)")
        case .notice: notice("\(message)")
        case .warning: warning("\(message)")
        case .error: error("\(message)")
        case .critical: critical("\(message)")
        }
    }
}
