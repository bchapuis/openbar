import Foundation

public enum HelperConstants {
    /// launchd label and Mach service name of the privileged helper.
    public static let label = "local.OpenBar.helper"
    /// Root-owned directory that holds the bundled openconnect and the helper's files.
    public static let supportDirectory = "/Library/Application Support/OpenBar"
    /// File with the hash of the installed payload, written at build time.
    public static let payloadVersionFile = "payload-version"
    /// File with the code-signing requirement that clients must satisfy.
    public static let clientRequirementFile = "client-requirement"

    public static let protocols = ["anyconnect", "gp", "nc", "pulse", "f5", "fortinet", "array"]

    /// The only extra openconnect options a client may pass. Options that run
    /// programs or read files (such as --script) must never be allowed here:
    /// the helper runs openconnect as root on behalf of an unprivileged app.
    public static let allowedOptionPrefixes = [
        "--servercert=", "--authgroup=", "--usergroup=", "--os=", "--useragent=",
        "--mtu=", "--no-dtls", "--force-dpd=", "--reconnect-timeout=",
    ]
}

/// XPC interface of the privileged helper.
@objc public protocol HelperProtocol {
    /// Hash of the installed payload. The app compares it with its own copy
    /// to know whether the helper must be updated.
    func payloadVersion(reply: @escaping (String) -> Void)

    /// Starts openconnect. Replies with an error message, or nil on success.
    func connect(server: String, user: String, vpnProtocol: String,
                 disableIPv6: Bool, hipReport: Bool, options: [String],
                 password: String, reply: @escaping (String?) -> Void)

    /// Stops openconnect. Replies once it has exited.
    func disconnect(reply: @escaping () -> Void)

    /// Replies with (state, address, error, connected since, new log lines, next line index).
    /// `state` is one of "disconnected", "connecting", "connected", "disconnecting".
    /// "Connected since" is in seconds since 1970, or 0 when not connected.
    /// Pass the last "next line index" as `since` to receive only new lines.
    func status(since: Int, reply: @escaping (String, String, String, Double, [String], Int) -> Void)
}
