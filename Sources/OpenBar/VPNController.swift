import AppKit
import Foundation
import HelperShared
import Security

enum VPNState: String {
    case disconnected, connecting, connected, disconnecting
}

enum HelperState {
    /// Not asked yet.
    case unknown
    /// Not installed, not reachable, or it refused this build of the app.
    case missing
    /// Installed from a different build; must be updated.
    case outdated
    case ready
}

/// Talks to the privileged helper, which owns the openconnect process.
///
/// The helper is the source of truth: the app polls it for the state and the
/// new log lines. The VPN therefore survives a restart of the app, and the app
/// picks the session up again when it starts.
@MainActor
final class VPNController: ObservableObject {
    static let shared = VPNController()

    @Published private(set) var helperState = HelperState.unknown
    /// What the administrator prompt is doing, while it runs ("Installing Helper…").
    @Published private(set) var helperTask: String?
    @Published private(set) var state = VPNState.disconnected
    @Published private(set) var address: String?
    @Published private(set) var connectedSince: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var log: [String] = []
    @Published var password = ""

    private var connection: NSXPCConnection?
    private var nextLine = 0
    private var requestInFlight = false
    /// Counts the commands sent to the helper. A status that was requested
    /// before the latest command describes the past and is dropped.
    private var commandCount = 0
    private var ticks = 0
    private var timer: Timer?
    /// Connect as soon as the helper installation that is under way succeeds.
    @Published private var pendingConnect = false

    private static let maxLogLines = 2000

    private init() {
        Settings.registerDefaults()
        loadPassword()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Common modes: keep polling while a menu is open or the app is quitting.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    // MARK: - Presentation

    var helperBusy: Bool { helperTask != nil }

    /// Status with details, for accessibility.
    var statusText: String {
        address.map { "\(title) (\($0))" } ?? title
    }

    /// Short status. A missing helper is not a state of its own: the VPN is
    /// simply not connected, and connecting installs the helper.
    var title: String {
        if let helperTask { return helperTask }
        if helperState == .unknown { return "Checking…" }
        switch state {
        case .disconnected: return "Not Connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting…"
        }
    }

    /// True while something is in progress.
    var isBusy: Bool {
        helperBusy || helperState == .unknown || state == .connecting || state == .disconnecting
    }

    /// True when the VPN is up or coming up.
    var isOn: Bool { pendingConnect || state == .connecting || state == .connected }

    /// Every value `symbolName` can take.
    nonisolated static let allSymbolNames = ["shield.slash", "shield.lefthalf.filled", "lock.shield.fill"]

    var symbolName: String {
        if helperBusy { return "shield.lefthalf.filled" }
        switch state {
        case .disconnected: return "shield.slash"
        case .connecting, .disconnecting: return "shield.lefthalf.filled"
        case .connected: return "lock.shield.fill"
        }
    }

    var needsHelperInstall: Bool { helperState == .missing || helperState == .outdated }
    var canConnect: Bool { state == .disconnected && !helperBusy && helperState != .unknown }
    var canDisconnect: Bool { helperState == .ready && (state == .connecting || state == .connected) }

    // MARK: - Password

    func loadPassword() {
        let s = Settings.load()
        password = s.isConfigured && s.savePassword
            ? Keychain.password(for: s.keychainAccount) ?? ""
            : ""
    }

    // MARK: - Connect and disconnect

    func connect() {
        guard canConnect else { return }
        errorMessage = nil

        let s = Settings.load()
        guard s.isConfigured else { return fail("Set the server and the user name first.") }
        guard !password.isEmpty else { return fail("Enter the password first.") }
        // Without the helper, install it first; `helperChecked` then connects.
        if needsHelperInstall {
            pendingConnect = true
            return installHelper()
        }
        if s.savePassword {
            Keychain.setPassword(password, for: s.keychainAccount)
        } else {
            Keychain.deletePassword(for: s.keychainAccount)
        }

        state = .connecting
        commandCount += 1
        helper()?.connect(server: s.server, user: s.user, vpnProtocol: s.vpnProtocol,
                          disableIPv6: s.disableIPv6, hipReport: s.hipReport,
                          options: s.options, password: password) { error in
            Task { @MainActor in
                if let error {
                    self.state = .disconnected
                    self.fail(error)
                }
            }
        }
    }

    func disconnect() {
        guard canDisconnect else { return }
        state = .disconnecting
        commandCount += 1
        helper()?.disconnect {}
    }

    /// Disconnects and waits for openconnect to exit. Used when the app quits.
    func shutdown() async {
        guard needsShutdown, let helper = helper() else { return }
        state = .disconnecting
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // The helper kills openconnect after 10 seconds at the latest.
            let once = Once { continuation.resume() }
            helper.disconnect { once.run() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 13) { once.run() }
        }
    }

    var needsShutdown: Bool { helperState == .ready && state != .disconnected }

    // MARK: - Polling

    private func tick() {
        ticks += 1
        // Poll fast while something is happening, slowly otherwise.
        let active = helperState == .ready && state != .disconnected
        if active || ticks % 10 == 0 { poll() }
    }

    private func poll() {
        guard !requestInFlight, !helperBusy, let helper = helper() else { return }
        requestInFlight = true
        if helperState != .ready {
            helper.payloadVersion { version in
                Task { @MainActor in
                    self.requestInFlight = false
                    self.helperState = version == Self.bundledPayloadVersion ? .ready : .outdated
                    self.helperChecked()
                    if self.helperState == .ready { self.poll() }
                }
            }
        } else {
            let requestedAt = commandCount
            helper.status(since: nextLine) { state, address, error, connectedSince, lines, next in
                Task { @MainActor in
                    self.requestInFlight = false
                    guard requestedAt == self.commandCount else { return }
                    self.apply(state: state, address: address, error: error,
                               connectedSince: connectedSince, lines: lines, next: next)
                }
            }
        }
    }

    private func apply(state: String, address: String, error: String,
                       connectedSince: Double, lines: [String], next: Int) {
        let since = connectedSince > 0 ? Date(timeIntervalSince1970: connectedSince) : nil
        if since != self.connectedSince { self.connectedSince = since }
        let newState = VPNState(rawValue: state) ?? .disconnected
        if newState != self.state { self.state = newState }
        let newAddress = address.isEmpty ? nil : address
        if newAddress != self.address { self.address = newAddress }
        if newState == .disconnected, !error.isEmpty, errorMessage == nil { errorMessage = error }
        if newState != .disconnected, errorMessage != nil { errorMessage = nil }
        nextLine = next
        if !lines.isEmpty { appendLog(lines) }
    }

    // MARK: - Helper connection

    private func helper() -> HelperProtocol? {
        if connection == nil {
            let new = HelperConnection.make()
            new.resume()
            connection = new
        }
        let current = connection
        return connection?.remoteObjectProxyWithErrorHandler { _ in
            Task { @MainActor in self.helperLost(current) }
        } as? HelperProtocol
    }

    /// The helper is not installed, crashed, or rejected this app.
    private func helperLost(_ lost: NSXPCConnection?) {
        guard lost === connection else { return }
        connection?.invalidate()
        connection = nil
        requestInFlight = false
        helperState = .missing
        state = .disconnected
        address = nil
        connectedSince = nil
        helperChecked()
    }

    /// Called when the helper's state is known again. Carries on with a
    /// connection that was waiting for the helper to be installed.
    private func helperChecked() {
        guard pendingConnect, !helperBusy else { return }
        pendingConnect = false
        if helperState == .ready {
            connect()
        } else {
            fail("The helper could not be installed. See the logs.")
        }
    }

    // MARK: - Helper installation

    func installHelper() {
        guard let resources = Bundle.main.resourcePath, let hash = Self.ownCodeHash() else {
            return fail("Cannot install the helper: the app is not a signed bundle.")
        }
        runAsAdministrator(task: helperState == .outdated ? "Updating Helper…" : "Installing Helper…",
                           script: resources + "/install-helper.sh", arguments: [resources, hash],
                           prompt: "OpenBar needs to install its helper to manage VPN connections.")
    }

    func uninstallHelper() {
        guard let resources = Bundle.main.resourcePath else { return }
        runAsAdministrator(task: "Removing Helper…",
                           script: resources + "/uninstall-helper.sh", arguments: [],
                           prompt: "OpenBar needs administrator rights to remove its helper.")
    }

    /// Runs a shell script as root through the standard macOS administrator prompt.
    private func runAsAdministrator(task: String, script: String, arguments: [String], prompt: String) {
        guard !helperBusy else { return }
        // The prompt belongs to another process. When it closes, macOS gives
        // the focus back to the previous regular app and this app's window
        // ends up behind it; remember to bring it back.
        let hadWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        let command = (["/bin/sh", script] + arguments).map(Shell.quote).joined(separator: " ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \(Self.appleScriptString(command))"
            + " with prompt \(Self.appleScriptString(prompt)) with administrator privileges"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { _ in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                self.helperTask = nil
                if hadWindow { AppDelegate.showMainWindow() }
                if text.contains("-128") {
                    self.appendLog(["Authorization cancelled."])
                    self.pendingConnect = false
                } else if !text.isEmpty {
                    self.appendLog(text.components(separatedBy: .newlines))
                }
                // Start again with a fresh connection to the new helper.
                self.connection?.invalidate()
                self.connection = nil
                self.requestInFlight = false
                self.helperState = .unknown
                self.poll()
            }
        }
        do {
            try process.run()
            helperTask = task
        } catch {
            pendingConnect = false
            fail("Could not ask for administrator rights: \(error.localizedDescription)")
        }
    }

    /// Hash of the helper payload shipped in this app bundle (written by build.sh).
    private static let bundledPayloadVersion: String = {
        guard let url = Bundle.main.url(forResource: HelperConstants.payloadVersionFile, withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "missing" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// The code directory hash of this app. The helper only accepts clients
    /// with this exact hash, so no other program can drive the helper.
    static func ownCodeHash() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Log

    func clearLog() { log.removeAll() }

    private func appendLog(_ lines: [String]) {
        log.append(contentsOf: lines)
        if log.count > Self.maxLogLines {
            log.removeFirst(log.count - Self.maxLogLines)
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        appendLog([message])
    }

    private static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Runs a closure at most once.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (() -> Void)?

    init(_ action: @escaping () -> Void) { self.action = action }

    func run() {
        lock.lock()
        let action = self.action
        self.action = nil
        lock.unlock()
        action?()
    }
}
