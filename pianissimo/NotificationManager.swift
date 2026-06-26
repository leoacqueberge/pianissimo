//
//  NotificationManager.swift
//  Pianissimo
//
//  Notifications locales macOS pour prévenir en fin de traitement.
//

import Foundation
import UserNotifications

enum NotificationManager {

    /// Demande l'autorisation d'envoyer des notifications (à appeler au lancement).
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Envoie une notification locale (titre + message).
    static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content, trigger: nil)
            center.add(request)
        }
    }
}
