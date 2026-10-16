import Combine
import CoreBluetooth
import Foundation
import NordicDFU

/// Recovers a bracelet stuck in firmware-update (DFU) mode: when one is found and the
/// official firmware for its model has been imported, it is reflashed automatically with
/// Nordic's DFU library (the same one inside nRF Device Firmware Update), and the app then
/// reconnects to the bracelet.
///
/// The firmware belongs to Impossible Labs and is not shipped in this open-source app; the
/// user imports the official file once (Files, or "Open in Bond Touch Beyond" from the
/// share sheet). It is kept in Application Support, one file per bracelet model.
@MainActor
final class FirmwareRecovery: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case needsFirmware(BraceletModel)
        case flashing(BraceletModel, progress: Int)
        case done(BraceletModel)
        case failed(BraceletModel, String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var installed: [BraceletModel: String] = [:]   // model → file name
    /// A firmware file opened from another app whose model couldn't be guessed from its name.
    @Published var pendingImport: URL?
    @Published var importError: String?

    private weak var bracelet: BraceletManager?
    private var controller: DFUServiceController?
    private var cancellable: AnyCancellable?
    private var attempts: [UUID: Int] = [:]

    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("firmware", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func url(for model: BraceletModel) -> URL { dir.appendingPathComponent(model.rawValue + ".zip") }

    func start(_ bracelet: BraceletManager) {
        self.bracelet = bracelet
        reloadInstalled()
        cancellable = bracelet.$dfuDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                guard let self, let device else { return }
                self.recover(device)
            }
    }

    private func reloadInstalled() {
        var out: [BraceletModel: String] = [:]
        for m in BraceletModel.allCases where FileManager.default.fileExists(atPath: Self.url(for: m).path) {
            out[m] = UserDefaults.standard.string(forKey: "FirmwareName." + m.rawValue) ?? "Firmware"
        }
        installed = out
    }

    /// Imports an official firmware package (.zip) for `model`. Checks it is a valid DFU package.
    func importFirmware(from source: URL, model: BraceletModel) throws {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: source)
        _ = try DFUFirmware(zipFile: data)   // throws if it isn't a DFU package
        try data.write(to: Self.url(for: model), options: .atomic)
        UserDefaults.standard.set(source.lastPathComponent, forKey: "FirmwareName." + model.rawValue)
        reloadInstalled()
        // A bracelet already waiting for this firmware gets it now.
        if let device = bracelet?.dfuDevice, device.model == model { recover(device) }
    }

    /// A .zip opened in the app ("Open in Bond Touch Beyond" / share sheet).
    func handleOpened(_ url: URL) {
        guard url.pathExtension.lowercased() == "zip" else { return }
        if let model = BraceletModel.guess(fromFileName: url.lastPathComponent) {
            do { try importFirmware(from: url, model: model); importError = nil }
            catch { importError = "That file isn't a bracelet firmware package." }
        } else {
            pendingImport = url
        }
    }

    func removeFirmware(_ model: BraceletModel) {
        try? FileManager.default.removeItem(at: Self.url(for: model))
        reloadInstalled()
    }

    /// Reflashes a bracelet found in update mode (at most 3 tries per bracelet).
    func recover(_ device: BraceletManager.DFUCandidate) {
        if case .flashing = phase { return }
        guard installed[device.model] != nil,
              let data = try? Data(contentsOf: Self.url(for: device.model)),
              let firmware = try? DFUFirmware(zipFile: data) else {
            phase = .needsFirmware(device.model)
            return
        }
        guard attempts[device.id, default: 0] < 3 else { return }
        attempts[device.id, default: 0] += 1
        bracelet?.pauseScanning()
        phase = .flashing(device.model, progress: 0)
        let initiator = DFUServiceInitiator(queue: .main).with(firmware: firmware)
        initiator.delegate = self
        initiator.progressDelegate = self
        initiator.alternativeAdvertisingNameEnabled = false
        controller = initiator.start(targetWithIdentifier: device.id)
    }

    func dismiss() {
        if case .flashing = phase { return }
        phase = .idle
    }

    private var currentModel: BraceletModel? {
        switch phase {
        case .flashing(let m, _), .needsFirmware(let m), .done(let m), .failed(let m, _): return m
        case .idle: return nil
        }
    }
}

extension FirmwareRecovery: DFUServiceDelegate, DFUProgressDelegate {
    nonisolated func dfuStateDidChange(to state: DFUState) {
        Task { @MainActor in
            guard let model = self.currentModel else { return }
            switch state {
            case .completed:
                self.phase = .done(model)
                self.controller = nil
                self.bracelet?.resumeAfterRecovery()
            case .aborted:
                self.phase = .failed(model, "The update was stopped.")
                self.controller = nil
                self.bracelet?.resumeAfterRecovery()
            default:
                break
            }
        }
    }

    nonisolated func dfuError(_ error: DFUError, didOccurWithMessage message: String) {
        Task { @MainActor in
            guard let model = self.currentModel else { return }
            self.phase = .failed(model, message)
            self.controller = nil
            self.bracelet?.resumeAfterRecovery()
        }
    }

    nonisolated func dfuProgressDidChange(for part: Int, outOf totalParts: Int, to progress: Int,
                                          currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
        Task { @MainActor in
            guard let model = self.currentModel else { return }
            self.phase = .flashing(model, progress: progress)
        }
    }
}
