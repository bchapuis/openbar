import Foundation
import HelperShared

/// Command-line modes of the app binary, for debugging and for the tests:
///
///     OpenBar --helper-check        print the helper's state and last log lines
///     OpenBar --helper-connect      connect with the saved settings (password on stdin)
///     OpenBar --helper-disconnect   disconnect
///     OpenBar --snapshot <dir>      render the views to PNG files
///
/// They live in the app binary because the helper only talks to that binary
/// (it checks the code hash of its client).
enum CommandLineTool {
    /// Runs the mode named in `arguments`. Returns false if there is none, in
    /// which case the caller starts the app. Otherwise it does not return.
    static func run(_ arguments: [String]) -> Bool {
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.count > index + 1 {
            MainActor.assumeIsolated { Snapshot.run(directory: arguments[index + 1]) }
        }
        let commands = ["--helper-check", "--helper-connect", "--helper-disconnect"]
        guard let command = arguments.dropFirst().first(where: commands.contains) else { return false }

        let connection = HelperConnection.make()
        connection.resume()
        let helper = connection.remoteObjectProxyWithErrorHandler { error in
            print("helper not reachable: \(error.localizedDescription)")
            exit(1)
        } as! HelperProtocol

        switch command {
        case "--helper-connect":
            Settings.registerDefaults()
            let settings = Settings.load()
            helper.connect(server: settings.server, user: settings.user, vpnProtocol: settings.vpnProtocol,
                           disableIPv6: settings.disableIPv6, hipReport: settings.hipReport,
                           options: settings.options, password: readLine() ?? "") { error in
                print(error ?? "started")
                exit(error == nil ? 0 : 1)
            }
        case "--helper-disconnect":
            helper.disconnect {
                print("disconnected")
                exit(0)
            }
        default:
            helper.payloadVersion { version in
                print("payload version: \(version)")
                helper.status(since: 0) { state, address, error, _, lines, _ in
                    print("state: \(state) \(address) \(error)")
                    lines.suffix(20).forEach { print("  \($0)") }
                    exit(0)
                }
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(15))
        print("helper did not answer")
        exit(1)
    }
}

enum HelperConnection {
    /// A connection to the helper, not yet resumed.
    ///
    /// Setting OPENCONNECT_MENU_TEST_SERVICE makes the app talk to a helper
    /// that runs as a user LaunchAgent under that name; the tests use this.
    static func make() -> NSXPCConnection {
        let connection: NSXPCConnection
        if let test = ProcessInfo.processInfo.environment["OPENCONNECT_MENU_TEST_SERVICE"] {
            connection = NSXPCConnection(machServiceName: test)
        } else {
            connection = NSXPCConnection(machServiceName: HelperConstants.label, options: .privileged)
        }
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        return connection
    }
}
