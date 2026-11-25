// Privileged helper: a launchd daemon that runs the bundled openconnect as
// root on behalf of the menu bar app.
//
// Usage: local.OpenBar.helper [--root <dir>] [--service <name>]
// The options exist for testing without root (as a user LaunchAgent).

import Foundation
import HelperShared

var root = HelperConstants.supportDirectory
var service = HelperConstants.label
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--root": root = arguments.next() ?? root
    case "--service": service = arguments.next() ?? service
    default: break
    }
}

let vpn = VPN(root: root)

/// Accepts only clients that satisfy the requirement recorded at install time
/// (the code hash of the app that installed the helper).
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let file = root + "/" + HelperConstants.clientRequirementFile
        guard let requirement = try? String(contentsOfFile: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !requirement.isEmpty
        else {
            NSLog("Rejecting client: cannot read \(file)")
            return false
        }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = vpn
        connection.resume()
        return true
    }
}

// launchd sends SIGTERM when the helper is updated or removed: stop the VPN first.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    vpn.disconnect { exit(0) }
}
termination.resume()

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: service)
listener.delegate = delegate
listener.resume()
dispatchMain()
