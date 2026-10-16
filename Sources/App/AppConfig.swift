import Foundation

/// App-wide identifiers in one place.
enum AppConfig {
    static let bundleID = "com.lightwave.beyond"
    /// CloudKit container — must match the iCloud entitlement (iCloud.<bundle id>).
    static let cloudContainerID = "iCloud.com.lightwave.beyond"
}
