import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UserNotifications

// MARK: - StoreRadarService

/// Opt-in location nudges: when you wander near a gas station, corner store,
/// or grocery, a notification asks the only question that matters.
///
/// Mechanics: significant-location-change wakeups refresh a small set of
/// geofences around nearby points of interest (MKLocalSearch); crossing into
/// one fires a local notification, throttled to one per 3 hours. Region
/// monitoring re-launches the app in the background, so nudges survive
/// force-quits — as long as the user granted Always authorization.
@MainActor
@Observable
final class StoreRadarService: NSObject {

    static let shared = StoreRadarService()

    nonisolated static let nudgeCategoryID = "CAN_RADAR"
    nonisolated static let actionLogUsual = "LOG_USUAL"
    nonisolated static let actionOpenScanner = "OPEN_SCANNER"

    private static let enabledKey = "storeRadar.enabled"
    private static let lastNudgeKey = "storeRadar.lastNudge"
    private static let nudgeCooldown: TimeInterval = 3 * 60 * 60

    private let manager = CLLocationManager()

    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var notificationsGranted = false

    var isEnabled: Bool = UserDefaults.standard.bool(forKey: StoreRadarService.enabledKey) {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                Task { await self.arm() }
            } else {
                disarm()
            }
        }
    }

    override private init() {
        super.init()
        manager.delegate = self
        locationStatus = manager.authorizationStatus
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsGranted = settings.authorizationStatus == .authorized
        }
    }

    /// One-line permission story for the profile card.
    var authorizationSummary: String {
        switch (locationStatus, notificationsGranted, isEnabled) {
        case (_, _, false):
            return "Off. Your whereabouts are your business."
        case (.denied, _, _), (.restricted, _, _):
            return "Location denied. Settings can fix that."
        case (_, false, _):
            return "Notifications denied. The radar has no voice."
        case (.authorizedAlways, true, _):
            return "Armed. We watch the gas stations so you don't have to."
        case (.authorizedWhenInUse, true, _):
            return "Foreground only — grant Always for the full radar."
        default:
            return "Waiting on permissions."
        }
    }

    var permissionsDenied: Bool {
        locationStatus == .denied || locationStatus == .restricted
            || (isEnabled && !notificationsGranted)
    }

    // MARK: Arming

    /// Called at launch: re-arm monitoring if the user opted in previously.
    func resumeIfEnabled() {
        guard isEnabled else { return }
        Task { await arm() }
    }

    private func arm() async {
        let center = UNUserNotificationCenter.current()
        if let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge]) {
            notificationsGranted = granted
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // didChangeAuthorization escalates to Always and starts monitoring.
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            startMonitoring()
        case .authorizedAlways:
            startMonitoring()
        default:
            break
        }
    }

    private func disarm() {
        manager.stopMonitoringSignificantLocationChanges()
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }

    private func startMonitoring() {
        manager.startMonitoringSignificantLocationChanges()
        if let location = manager.location {
            Task { await refreshGeofences(around: location.coordinate) }
        }
    }

    // MARK: Geofence refresh

    /// Replace the monitored regions with the nearest can-adjacent businesses.
    private func refreshGeofences(around center: CLLocationCoordinate2D) async {
        guard isEnabled else { return }

        let request = MKLocalPointsOfInterestRequest(center: center, radius: 600)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .gasStation, .foodMarket, .store,
        ])

        guard let response = try? await MKLocalSearch(request: request).start() else { return }

        for region in manager.monitoredRegions where region.identifier.hasPrefix("radar.") {
            manager.stopMonitoring(for: region)
        }

        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let nearest = response.mapItems
            .sorted {
                let a = CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)
                let b = CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude)
                return a.distance(from: origin) < b.distance(from: origin)
            }
            .prefix(12)

        for (index, item) in nearest.enumerated() {
            let name = item.name ?? "a store"
            let region = CLCircularRegion(
                center: item.placemark.coordinate,
                radius: 120,
                identifier: "radar.\(index).\(name.prefix(24))"
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    // MARK: Nudge

    private func nudge(placeName: String) {
        guard isEnabled, notificationsGranted else { return }

        let now = Date()
        if let last = UserDefaults.standard.object(forKey: Self.lastNudgeKey) as? Date,
           now.timeIntervalSince(last) < Self.nudgeCooldown {
            return
        }
        UserDefaults.standard.set(now, forKey: Self.lastNudgeKey)

        scheduleNudge(placeName: placeName, delay: 1)
    }

    private func scheduleNudge(placeName: String, delay: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "At \(placeName)?"
        content.body = "If a Red Bull happened, log it. No judgment. Some judgment."
        content.sound = .default
        content.categoryIdentifier = Self.nudgeCategoryID

        let request = UNNotificationRequest(
            identifier: "radar.nudge.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// DEBUG hook: fire the exact nudge 3 seconds out, no geofence required.
    func fireTestNudge() {
        Task {
            let center = UNUserNotificationCenter.current()
            if let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge]) {
                notificationsGranted = granted
            }
            scheduleNudge(placeName: "The Corner Store", delay: 3)
        }
    }

    /// Registers the notification category + actions. Call once at launch.
    static func registerNotificationCategory() {
        let logUsual = UNNotificationAction(
            identifier: actionLogUsual,
            title: "Log my usual",
            options: []
        )
        let openScanner = UNNotificationAction(
            identifier: actionOpenScanner,
            title: "Scan it",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: nudgeCategoryID,
            actions: [logUsual, openScanner],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - CLLocationManagerDelegate

extension StoreRadarService: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationStatus = status
            guard self.isEnabled else { return }
            switch status {
            case .authorizedWhenInUse:
                self.manager.requestAlwaysAuthorization()
                self.startMonitoring()
            case .authorizedAlways:
                self.startMonitoring()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            await self.refreshGeofences(around: coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("radar.") else { return }
        let name = region.identifier
            .split(separator: ".", maxSplits: 2)
            .last.map(String.init) ?? "a store"
        Task { @MainActor in
            self.nudge(placeName: name)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location hiccups are not our problem; the next significant change retries.
    }
}

// MARK: - NotificationRouter

/// UNUserNotificationCenter delegate: shows radar nudges while foregrounded
/// and handles the "Log my usual" background action by logging the most
/// recently logged SKU straight into the shared container.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationRouter()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        guard actionID == StoreRadarService.actionLogUsual else {
            // OPEN_SCANNER and the default tap both foreground the app; Home's
            // scan button is one thumb away. Deep-link left for CloudKit-era polish.
            return
        }
        await MainActor.run {
            guard let container = CanCountApp.sharedContainer else { return }
            let context = container.mainContext
            var descriptor = FetchDescriptor<CanLog>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            descriptor.fetchLimit = 1
            let lastSKU = (try? context.fetch(descriptor))?.first?.sku
            let fallback = try? context.fetch(FetchDescriptor<SKU>()).first
            guard let sku = lastSKU ?? fallback else { return }
            LogPipeline.log(sku: sku, source: .manual, context: context)
        }
    }
}
