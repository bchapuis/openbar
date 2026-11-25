import Foundation

/// What a client asks the helper to connect to.
///
/// The helper runs openconnect as root on behalf of an unprivileged app, so
/// every field is validated before it reaches the command line.
public struct ConnectionRequest: Equatable, Sendable {
    public var server: String
    public var user: String
    public var vpnProtocol: String
    public var disableIPv6: Bool
    public var hipReport: Bool
    public var options: [String]

    public init(server: String, user: String, vpnProtocol: String,
                disableIPv6: Bool = false, hipReport: Bool = false, options: [String] = []) {
        self.server = server
        self.user = user
        self.vpnProtocol = vpnProtocol
        self.disableIPv6 = disableIPv6
        self.hipReport = hipReport
        self.options = options
    }

    /// Returns why the request (or the password) is not acceptable, or nil.
    public func validationError(password: String) -> String? {
        // A host name, optionally with a port and a path. It must not start
        // with "-", or openconnect would read it as an option.
        guard server.wholeMatch(of: #/[A-Za-z0-9][A-Za-z0-9.\-]*(:[0-9]+)?(/[A-Za-z0-9._/\-]*)?/#) != nil else {
            return "Invalid server name."
        }
        guard !user.isEmpty, !user.contains(where: \.isNewline) else { return "Invalid user name." }
        guard HelperConstants.protocols.contains(vpnProtocol) else { return "Invalid protocol." }
        // The password goes to openconnect as one line on its standard input.
        guard !password.isEmpty, !password.contains(where: \.isNewline) else { return "Invalid password." }
        for option in options {
            guard HelperConstants.allowedOptionPrefixes.contains(where: option.hasPrefix) else {
                return "Option not allowed: \(option)"
            }
        }
        return nil
    }

    /// The openconnect arguments for this request.
    ///
    /// `bundle` is the directory that holds the bundled openconnect
    /// (`bin/`, `libexec/`, `etc/`).
    public func arguments(bundle: String) -> [String] {
        var arguments = ["--protocol=\(vpnProtocol)", "--user=\(user)"]
        if disableIPv6 { arguments.append("--disable-ipv6") }
        if hipReport { arguments.append("--csd-wrapper=\(bundle)/libexec/hipreport.sh") }
        arguments += [
            // openconnect passes this to /bin/sh as a command line, and the
            // installed path contains a space ("Application Support"): quote it.
            "--script=" + Shell.quote("\(bundle)/etc/vpnc-script"),
            // Verify the server against the bundled, root-owned CA file only.
            "--no-system-trust", "--cafile=\(bundle)/etc/cert.pem",
        ]
        arguments += options
        // The password is read once from stdin; never wait for interactive input.
        arguments += ["--passwd-on-stdin", "--non-inter", server]
        return arguments
    }
}

public enum Shell {
    /// Quotes a string so that /bin/sh reads it as a single word.
    public static func quote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
