import Foundation
import HelperShared

/// Owns the openconnect process. All state is confined to `queue`.
final class VPN: NSObject, HelperProtocol, @unchecked Sendable {
    private enum State: String {
        case disconnected, connecting, connected, disconnecting
    }

    private let root: String
    private let queue = DispatchQueue(label: "vpn")

    private var state = State.disconnected
    private var address = ""
    private var connectedSince: Date?
    private var lastError = ""
    private var process: Process?
    private var userStopped = false
    private var disconnectReplies: [() -> Void] = []

    private var log = LogBuffer()
    private var splitter = LineSplitter()

    init(root: String) {
        self.root = root
    }

    // MARK: - HelperProtocol

    func payloadVersion(reply: @escaping (String) -> Void) {
        let file = root + "/" + HelperConstants.payloadVersionFile
        let version = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        reply(version.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func connect(server: String, user: String, vpnProtocol: String,
                 disableIPv6: Bool, hipReport: Bool, options: [String],
                 password: String, reply: @escaping (String?) -> Void) {
        let request = ConnectionRequest(server: server, user: user, vpnProtocol: vpnProtocol,
                                        disableIPv6: disableIPv6, hipReport: hipReport, options: options)
        queue.async {
            reply(self.start(request, password: password))
        }
    }

    func disconnect(reply: @escaping () -> Void) {
        queue.async {
            guard let process = self.process else { return reply() }
            self.disconnectReplies.append(reply)
            guard self.state != .disconnecting else { return }
            self.userStopped = true
            self.state = .disconnecting
            // SIGINT makes openconnect log off and restore routes and DNS.
            // Escalate if it does not exit.
            process.interrupt()
            self.queue.asyncAfter(deadline: .now() + 6) {
                if self.process === process { process.terminate() }
            }
            self.queue.asyncAfter(deadline: .now() + 10) {
                if self.process === process { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    func status(since: Int, reply: @escaping (String, String, String, Double, [String], Int) -> Void) {
        queue.async {
            reply(self.state.rawValue, self.address, self.lastError,
                  self.connectedSince?.timeIntervalSince1970 ?? 0,
                  self.log.lines(since: since), self.log.endIndex)
        }
    }

    // MARK: - Process

    /// Returns an error message, or nil when openconnect was started.
    private func start(_ request: ConnectionRequest, password: String) -> String? {
        guard process == nil else { return "A connection is already active." }
        // Everything here comes from an unprivileged client: validate it.
        if let error = request.validationError(password: password) { return error }

        removeStaleNetworkState()

        let bundle = root + "/openconnect"
        let arguments = request.arguments(bundle: bundle)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bundle + "/bin/openconnect")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            // Ignore the GnuTLS configuration file of the Homebrew build.
            "GNUTLS_SYSTEM_PRIORITY_FILE": "/dev/null",
        ]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                self?.queue.async { self?.receive(data) }
            }
        }
        process.terminationHandler = { [weak self] process in
            self?.queue.async { self?.finished(process) }
        }

        append("$ openconnect " + arguments.joined(separator: " "))
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            append("Could not start openconnect: \(error.localizedDescription)")
            return "Could not start openconnect: \(error.localizedDescription)"
        }
        input.fileHandleForWriting.write(Data((password + "\n").utf8))
        try? input.fileHandleForWriting.close()

        self.process = process
        userStopped = false
        lastError = ""
        address = ""
        state = .connecting
        return nil
    }

    private func finished(_ process: Process) {
        guard self.process === process else { return }
        if !userStopped {
            lastError = state == .connected
                ? "Connection lost. See the logs."
                : (log.lastMessage ?? "Connection failed. See the logs.")
        }
        append("openconnect exited (status \(process.terminationStatus)).")
        if process.terminationReason == .uncaughtSignal {
            removeStaleNetworkState()
        }
        self.process = nil
        address = ""
        connectedSince = nil
        state = .disconnected
        disconnectReplies.forEach { $0() }
        disconnectReplies.removeAll()
    }

    /// A killed openconnect cannot run vpnc-script to undo its changes. The
    /// DNS entries that vpnc-script registered under the tunnel device name
    /// then stay and break name resolution, including that of the VPN server.
    /// Remove the entries whose tunnel device no longer exists.
    private func removeStaleNetworkState() {
        let cleanup = Process()
        let output = Pipe()
        cleanup.executableURL = URL(fileURLWithPath: "/bin/sh")
        cleanup.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        cleanup.standardOutput = output
        cleanup.arguments = ["-c", """
            echo 'list State:/Network/Service/utun[0-9]+/.*' | scutil | sed -n 's/.* = //p' |
            while read key; do
                device=$(echo "$key" | cut -d/ -f4)
                ifconfig "$device" > /dev/null 2>&1 && continue
                echo "remove $key" | scutil
                echo "$key"
            done
            """]
        guard (try? cleanup.run()) != nil else { return }
        let removed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        cleanup.waitUntilExit()
        for key in removed.split(separator: "\n") {
            append("Removed leftover network settings of an earlier session: \(key)")
        }
    }

    private func receive(_ data: Data) {
        for line in splitter.append(data) {
            append(line)
            if state == .connecting, let tunnelAddress = OpenConnectOutput.tunnelAddress(in: line) {
                address = tunnelAddress
                connectedSince = Date()
                state = .connected
            }
        }
    }

    private func append(_ line: String) {
        log.append(line)
    }
}
