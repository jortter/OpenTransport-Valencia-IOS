import Foundation
import UserNotifications
import OpenTransportCore

/// Port of the pins loop in EmtApp.kt and of Notifier.kt: every minute, a
/// pinned stop+line within `alert_minutes` of arriving posts a notification
/// (at most once per 10 minutes per pin). iOS only runs this while the app is
/// open or was just backgrounded.
@MainActor
final class ArrivalAlerts {
    static let pinsKey = "pins"
    static let minutesKey = "alert_minutes"
    static let defaultMinutes = 10

    private var task: Task<Void, Never>?
    private var notified: [String: Date] = [:]

    static func stopPin(_ stopId: Int, _ line: String) -> String { "\(stopId):\(line)" }
    static func metrobusPin(_ placeId: String, _ line: String) -> String { "\(placeId):\(line)" }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func start(model: AppModel) {
        task?.cancel()
        task = Task { [weak self, weak model] in
            while !Task.isCancelled {
                guard let self, let model else { return }
                await self.check(model)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func check(_ model: AppModel) async {
        let limit = UserDefaults.standard.object(forKey: Self.minutesKey) as? Int ?? Self.defaultMinutes
        for pin in model.pins {
            guard let separator = pin.lastIndex(of: ":") else { continue }
            let target = String(pin[..<separator])
            let line = String(pin[pin.index(after: separator)...])
            let minutes: Int?
            let name: String
            let network: Network
            if target.hasPrefix("mb-") {
                network = .metrobus
                name = model.place(target)?.name ?? target
                let arrival = await model.metrobus.arrivals(code: String(target.dropFirst(3))).first { $0.line == line }
                minutes = arrival.flatMap { $0.minutes.firstMatchInt() }
            } else {
                network = .emt
                name = model.transit?.stopsById[target]?.cleanName ?? target
                guard let stopId = Int(target), let client = model.client else { continue }
                minutes = await client.nextBus(stopId: stopId, line: line)
            }
            guard let minutes, (1...limit).contains(minutes),
                  Date().timeIntervalSince(notified[pin] ?? .distantPast) > 10 * 60 else { continue }
            notified[pin] = Date()
            post(pin: pin, line: line, network: network, stopName: name, minutes: minutes)
        }
    }

    private func post(pin: String, line: String, network: Network, stopName: String, minutes: Int) {
        let content = UNMutableNotificationContent()
        let shownLine = network == .metrobus ? String(line.dropFirst(2)) : line
        content.title = "\(shownLine) · \(minutes) min"
        content.body = stopName
        content.sound = .default
        let request = UNNotificationRequest(identifier: "arrival-\(pin)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Shows arrival alerts as banners even while the app is in front.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

private extension String {
    /// Leading number of "12 min · Baja" → 12.
    func firstMatchInt() -> Int? {
        Int(prefix(while: \.isNumber))
    }
}
