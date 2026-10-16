import CloudKit
import Combine
import Foundation
import SwiftUI

/// Ties the iCloud relay to the bracelet. Owns app state the views render.
@MainActor
final class AppModel: ObservableObject {
    @Published var bond: Bond?
    @Published var history: [TouchMessage] = []   // sent + received, newest last
    @Published var statusLine: String = "Starting…"
    @Published var pendingShare: CKShare?
    @Published var braceletState: BraceletState = .disconnected
    @Published private(set) var myUserID: String = ""

    let bracelet = BraceletManager()
    let store = LocalStore()
    private let relay = CloudRelay()

    init() {
        // Re-publish the nested bracelet's state so SwiftUI views observing AppModel update.
        bracelet.$state.receive(on: DispatchQueue.main).assign(to: &$braceletState)
    }

    func bootstrap() async {
        guard await relay.accountIsAvailable() else {
            statusLine = "Sign in to iCloud to use Bond Touch Beyond."
            return
        }
        do {
            myUserID = try await relay.currentUserID()
            statusLine = "Ready."
            bracelet.startScanning()
        } catch {
            statusLine = "iCloud error: \(error.localizedDescription)"
        }

        // Relay a local tap out to the partner through iCloud.
        bracelet.onLocalTap = { [weak self] pattern in
            Task { await self?.sendTouch(pattern: pattern, colorRGB: 0xFF4081) }
        }
    }

    func createBond(displayName: String) async {
        do {
            let (bond, share) = try await relay.createBond(displayName: displayName)
            self.bond = bond
            self.pendingShare = share
        } catch {
            statusLine = "Couldn't create bond: \(error.localizedDescription)"
        }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do { self.bond = try await relay.acceptShare(metadata) }
        catch { statusLine = "Couldn't join bond: \(error.localizedDescription)" }
    }

    /// Sends a touch: out to the partner via iCloud. (The partner's device forwards
    /// it to their bracelet on receipt.)
    func sendTouch(pattern: [Int], colorRGB: Int) async {
        guard let bond else { return }
        let touch = TouchMessage(senderID: myUserID, pattern: pattern, colorRGB: colorRGB)
        do {
            try await relay.sendTouch(touch, bond: bond)
            history.append(touch)
        } catch { statusLine = "Send failed: \(error.localizedDescription)" }
    }

    /// Called when a silent push wakes us: pull new touches and play them.
    func handleRemoteNotification() async {
        guard let bond else { return }
        do {
            let touches = try await relay.fetchNewTouches(bond: bond, myUserID: myUserID)
            history.append(contentsOf: touches)
            if !store.doNotDisturb {
                for touch in touches { bracelet.play(touch) }
            }
        } catch {
            statusLine = "Fetch failed: \(error.localizedDescription)"
        }
    }
}
