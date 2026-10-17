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
///
/// It also runs the firmware updates the user asks for (`startUpdate`): the connected
/// bracelet is restarted in update mode, and when it reappears there it is flashed the
/// same way, with the built-in file for its generation.
@MainActor
final class FirmwareRecovery: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case needsFirmware(BraceletModel)
        /// An update was started: waiting for the bracelet to come back in update mode.
        case restarting(BraceletModel)
        case flashing(BraceletModel, progress: Int)
        case done(BraceletModel)
        case failed(BraceletModel, String)
    }

    @Published private(set) var phase: Phase = .idle
    /// True while the phases are those of an update the user asked for (not a repair).
    @Published private(set) var isUpdate = false
    /// The update in progress: its model and the built-in file for the bracelet's generation.
    private var intended: (model: BraceletModel, file: URL)?
    private var restartTimeout: Timer?
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

    /// Official firmware bundled in the app at build time (scripts/fetch-bracelet-firmware.sh),
    /// in the order to try. Both the Bond Touch (v2) and the classic one on the older
    /// hardware (v1) restart as BOND_DFU; a bootloader rejects the wrong image safely, so
    /// both are tried.
    static func bundledFirmware(for model: BraceletModel) -> [URL] {
        let names = model == .bondTouch ? ["bondTouch", "bondTouch-hw203"] : [model.rawValue]
        return names.compactMap { Bundle.main.url(forResource: $0, withExtension: "zip") }
    }

    func hasBuiltIn(_ model: BraceletModel) -> Bool { !Self.bundledFirmware(for: model).isEmpty }

    /// Firmware files to try for a model: an imported one first, then the built-in ones.
    private func candidates(for model: BraceletModel) -> [URL] {
        (installed[model] != nil ? [Self.url(for: model)] : []) + Self.bundledFirmware(for: model)
    }

    /// Updates the connected bracelet to the firmware built into the app, as the original:
    /// battery above 40 % (or on the charger), restart it in update mode, then — when it
    /// reappears as BOND_…_DFU — flash it automatically with its generation's file.
    func startUpdate(_ update: BraceletManager.FirmwareUpdate) {
        guard let bracelet else { return }
        switch phase {
        case .restarting, .flashing: return
        default: break
        }
        isUpdate = true
        guard bracelet.batteryAllowsUpdate else {
            phase = .failed(update.model, "Battery too low. Please charge your bracelet to install an update.")
            return
        }
        guard bracelet.enterUpdateMode() else {
            phase = .failed(update.model, "The bracelet isn't connected.")
            return
        }
        intended = (update.model, update.file)
        phase = .restarting(update.model)
        // The original gives up when no bootloader shows up (3 scans of 8 s after the command).
        restartTimeout?.invalidate()
        let t = Timer(timeInterval: 45, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.restartTimedOut() }
        }
        RunLoop.main.add(t, forMode: .common)
        restartTimeout = t
    }

    private func restartTimedOut() {
        restartTimeout = nil
        guard case .restarting(let m) = phase else { return }
        intended = nil
        phase = .failed(m, "The bracelet didn't restart in update mode.")
        bracelet?.endUpdateHandoff()
    }

    /// Reflashes a bracelet found in update mode — automatically, with the firmware that
    /// matches its model (for an update we started, the built-in file for its generation
    /// first). Each retry moves to the next candidate file.
    func recover(_ device: BraceletManager.DFUCandidate) {
        if case .flashing = phase { return }
        var model = device.model
        var files = candidates(for: model)
        // A Bond Mini may restart as BOND_4_DFU (the original accepts BT4 or mini for it).
        if let intended, intended.model == device.model || (intended.model == .bondMini && device.model == .bondTouch4) {
            model = intended.model
            files = [intended.file] + candidates(for: model).filter { $0 != intended.file }
        }
        isUpdate = intended != nil
        guard !files.isEmpty else { phase = .needsFirmware(model); return }
        let attempt = attempts[device.id, default: 0]
        guard attempt < max(3, files.count * 2) else { return }
        attempts[device.id] = attempt + 1
        guard let data = try? Data(contentsOf: files[attempt % files.count]),
              let firmware = try? DFUFirmware(zipFile: data) else {
            phase = .failed(model, "The firmware file couldn't be read.")
            return
        }
        restartTimeout?.invalidate()
        restartTimeout = nil
        bracelet?.pauseScanning()
        phase = .flashing(model, progress: 0)
        let initiator = DFUServiceInitiator(queue: .main).with(firmware: firmware)
        initiator.delegate = self
        initiator.progressDelegate = self
        initiator.alternativeAdvertisingNameEnabled = false
        controller = initiator.start(targetWithIdentifier: device.id)
    }

    /// After a failed try: rescan; the bracelet reappears in update mode and the next
    /// candidate firmware is tried automatically.
    func retrySoon() {
        bracelet?.dfuDevice = nil
        bracelet?.resumeAfterRecovery()
    }

    func dismiss() {
        switch phase {
        case .flashing, .restarting: return
        default: break
        }
        phase = .idle
        isUpdate = false
        intended = nil
    }

    private var currentModel: BraceletModel? {
        switch phase {
        case .flashing(let m, _), .needsFirmware(let m), .restarting(let m), .done(let m), .failed(let m, _): return m
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
                self.intended = nil
                self.bracelet?.resumeAfterRecovery()
            case .aborted:
                self.phase = .failed(model, "The update was stopped.")
                self.controller = nil
                self.retrySoon()
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
            self.retrySoon()
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
