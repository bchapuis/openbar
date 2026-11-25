import Foundation

/// UserDefaults keys, shared between `@AppStorage` in the views and `Settings.load()`.
enum SettingsKey {
    static let server = "server"
    static let user = "user"
    static let vpnProtocol = "protocol"
    static let disableIPv6 = "disableIPv6"
    static let hipReport = "hipReport"
    static let extraOptions = "extraOptions"
    static let savePassword = "savePassword"
}

struct Settings {
    var server: String
    var user: String
    var vpnProtocol: String
    var disableIPv6: Bool
    var hipReport: Bool
    var extraOptions: String
    var savePassword: Bool

    var isConfigured: Bool { !server.isEmpty && !user.isEmpty }

    /// Account name under which the password is stored in the keychain.
    var keychainAccount: String { "\(user)@\(server)" }

    /// Extra openconnect options, split on white space. The helper only
    /// accepts the ones listed in `HelperConstants.allowedOptionPrefixes`.
    var options: [String] {
        extraOptions.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.vpnProtocol: "gp",
            SettingsKey.disableIPv6: true,
            SettingsKey.hipReport: true,
            SettingsKey.savePassword: true,
        ])
    }

    static func load() -> Settings {
        let d = UserDefaults.standard
        func string(_ key: String) -> String {
            (d.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Settings(
            server: string(SettingsKey.server),
            user: string(SettingsKey.user),
            vpnProtocol: string(SettingsKey.vpnProtocol),
            disableIPv6: d.bool(forKey: SettingsKey.disableIPv6),
            hipReport: d.bool(forKey: SettingsKey.hipReport),
            extraOptions: string(SettingsKey.extraOptions),
            savePassword: d.bool(forKey: SettingsKey.savePassword)
        )
    }
}
