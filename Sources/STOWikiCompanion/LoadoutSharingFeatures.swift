import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct ShipLoadoutArchive: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let loadouts: [AdvancedShipLoadout]
}

struct ShipLoadoutArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var archive: ShipLoadoutArchive

    init(loadouts: [AdvancedShipLoadout]) {
        archive = ShipLoadoutArchive(formatVersion: 1, exportedAt: Date(), loadouts: loadouts)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        archive = try JSONDecoder().decode(ShipLoadoutArchive.self, from: data)
        guard archive.formatVersion == 1 else {
            throw NSError(domain: "STOWikiLoadoutArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: "This loadout archive version is not supported."])
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(archive))
    }
}

@MainActor
final class CampaignReminderService {
    static let shared = CampaignReminderService()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func schedule(for campaign: EventCampaignRecord) async throws {
        let settings = await center.notificationSettings()
        let granted: Bool
        if settings.authorizationStatus == .notDetermined {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } else {
            granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
        guard granted else {
            throw NSError(domain: "STOWikiReminder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Notifications are not authorized. Enable them for STO Wiki Companion in iOS Settings."])
        }

        let startID = "campaign-start-\(campaign.id.uuidString)"
        let endID = "campaign-end-\(campaign.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [startID, endID])

        let now = Date()
        if campaign.startDate > now {
            let start = UNMutableNotificationContent()
            start.title = "Campaign begins"
            start.body = "\(campaign.name) starts today. Check your participation and reward goals."
            start.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: campaign.startDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: startID, content: start, trigger: trigger))
        }

        if campaign.endDate > now {
            let end = UNMutableNotificationContent()
            end.title = "Campaign ending soon"
            end.body = "\(campaign.name) is scheduled to end tomorrow. Review your progress."
            end.sound = .default
            let reminderDate = Calendar.current.date(byAdding: .day, value: -1, to: campaign.endDate) ?? campaign.endDate
            if reminderDate > now {
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try await center.add(UNNotificationRequest(identifier: endID, content: end, trigger: trigger))
            }
        }
    }

    func cancel(for campaign: EventCampaignRecord) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "campaign-start-\(campaign.id.uuidString)",
            "campaign-end-\(campaign.id.uuidString)"
        ])
    }
}
