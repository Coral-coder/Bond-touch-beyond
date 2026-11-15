import CoreLocation
import Foundation

extension AppModel {
    /// Within this distance of each other counts as meeting (about 100 ft).
    static let meetingRadius: CLLocationDistance = 30
    /// Both locations must be at least this recent to count.
    static let meetingFixMaxAge: TimeInterval = 15 * 60

    /// On the day you planned to meet, being together (both phones within about 100 ft, with
    /// fresh locations) clears the "You meet today" countdown. A date whose day has passed is
    /// cleared too, so the countdown never sticks.
    func checkMeetings() {
        store.pruneEncounters()
        guard let me = location.lastLocation, Date().timeIntervalSince(me.timestamp) < Self.meetingFixMaxAge,
              me.horizontalAccuracy >= 0, me.horizontalAccuracy < 100 else { return }
        let cal = Calendar.current
        for partner in partners {
            guard let date = store.nextMeeting(for: partner.id), cal.isDateInToday(date),
                  let lat = partner.latitude, let lng = partner.longitude else { continue }
            if let at = partner.presence?.locationAt, Date().timeIntervalSince(at) > Self.meetingFixMaxAge { continue }
            let meters = me.distance(from: CLLocation(latitude: lat, longitude: lng))
            guard meters <= Self.meetingRadius else { continue }
            setNextMeeting(nil, for: partner.id)
            NetLog.shared.log(.ok, "Together with \(partner.displayName): meeting countdown cleared")
        }
    }
}
