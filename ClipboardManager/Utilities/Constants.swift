// Constants.swift
import Foundation

struct Constants {
    static let maxHistoryItems = 100
    static let maxHistoryDays = 7
}

extension Notification.Name {
    static let openSettingsRequest = Notification.Name("OpenSettingsRequest")
}
