// Constants.swift
import Foundation

struct Constants {
    static let appName = "Clipboard Manager"
    static let maxHistoryItems = 100
    static let maxHistoryDays = 7
    static let defaultSearchPlaceholder = "Search clipboard history..."
    static let clipboardItemDeletedNotification = Notification.Name("ClipboardItemDeleted")
    static let clipboardItemAddedNotification = Notification.Name("ClipboardItemAdded")
    static let clipboardItemUpdatedNotification = Notification.Name("ClipboardItemUpdated")
}

extension Notification.Name {
    static let openSettingsRequest = Notification.Name("OpenSettingsRequest")
}