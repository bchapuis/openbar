import HelperShared
import SwiftUI

/// The main window: a status header above three tabs.
struct MainView: View {
    @EnvironmentObject private var vpn: VPNController
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        VStack(spacing: 0) {
            StatusHero()
            Picker("Section", selection: $navigation.tab) {
                ForEach(Navigation.Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.bottom, 4)

            switch navigation.tab {
            case .connection: ConnectionTab()
            case .advanced: AdvancedTab()
            case .logs: LogTab()
            }
        }
        .frame(minWidth: 440, minHeight: 560)
        // The state color fades in from the top of the window.
        .background(alignment: .top) {
            LinearGradient(colors: [vpn.tint.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
                .ignoresSafeArea()
                .animation(.smooth(duration: 0.6), value: vpn.tint)
        }
    }
}

/// Large status display with the main action.
private struct StatusHero: View {
    @EnvironmentObject private var vpn: VPNController
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        VStack(spacing: 10) {
            StatusBadge(size: 76)
            VStack(spacing: 3) {
                Text(vpn.title)
                    .font(.title2.weight(.semibold))
                    .contentTransition(.opacity)
                StatusDetail()
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 18)
                if vpn.errorMessage != nil, vpn.state == .disconnected, navigation.tab != .logs {
                    Button("Show Logs") { navigation.tab = .logs }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
            action
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .animation(.smooth, value: vpn.title)
    }

    @ViewBuilder private var action: some View {
        if vpn.isOn || vpn.state == .disconnecting {
            Button("Disconnect") { vpn.disconnect() }
                .disabled(!vpn.canDisconnect)
        } else {
            Button("Connect") { vpn.connect() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!vpn.canConnect)
        }
    }
}

/// Server and account.
private struct ConnectionTab: View {
    @EnvironmentObject private var vpn: VPNController

    @AppStorage(SettingsKey.server) private var server = ""
    @AppStorage(SettingsKey.user) private var user = ""
    @AppStorage(SettingsKey.vpnProtocol) private var vpnProtocol = "gp"
    @AppStorage(SettingsKey.savePassword) private var savePassword = true

    private static let protocolNames = [
        "anyconnect": "Cisco AnyConnect",
        "gp": "Palo Alto GlobalProtect",
        "nc": "Juniper Network Connect",
        "pulse": "Pulse Connect Secure",
        "f5": "F5 BIG-IP",
        "fortinet": "Fortinet",
        "array": "Array Networks",
    ]

    var body: some View {
        Form {
            Section("Server") {
                TextField("Address", text: $server, prompt: Text("vpn.example.com"))
                Picker("Protocol", selection: $vpnProtocol) {
                    ForEach(HelperConstants.protocols, id: \.self) {
                        Text(Self.protocolNames[$0] ?? $0).tag($0)
                    }
                }
            }
            Section {
                TextField("User", text: $user, prompt: Text("user@example.com"))
                SecureField("Password", text: $vpn.password)
                Toggle("Save password in the keychain", isOn: $savePassword)
            } header: {
                Text("Account")
            } footer: {
                if vpn.state != .disconnected {
                    Text("Disconnect to change these settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .autocorrectionDisabled()
        .disabled(vpn.state != .disconnected)
        // The saved password belongs to a user and server pair.
        .onChange(of: server) { vpn.loadPassword() }
        .onChange(of: user) { vpn.loadPassword() }
    }
}

/// Connection options and the privileged helper.
private struct AdvancedTab: View {
    @EnvironmentObject private var vpn: VPNController

    @AppStorage(SettingsKey.disableIPv6) private var disableIPv6 = true
    @AppStorage(SettingsKey.hipReport) private var hipReport = true
    @AppStorage(SettingsKey.extraOptions) private var extraOptions = ""

    @State private var confirmingUninstall = false

    private var helperStatus: String {
        switch vpn.helperState {
        case .unknown: return "Checking…"
        case .missing: return "Not installed"
        case .outdated: return "Needs an update"
        case .ready: return "Installed"
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Disable IPv6", isOn: $disableIPv6)
                Toggle("Send HIP report", isOn: $hipReport)
                TextField("Extra options", text: $extraOptions, prompt: Text("--servercert=…"))
            } header: {
                Text("Options")
            } footer: {
                Text("The HIP report is what GlobalProtect servers use to check the computer. Extra options are passed to openconnect; only a few safe ones are accepted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(vpn.state != .disconnected)

            Section {
                LabeledContent("Status") {
                    Label(helperStatus, systemImage: vpn.helperState == .ready
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(vpn.helperState == .ready ? .green : .orange)
                }
                // One action per state: install it, update it, or remove it.
                if vpn.helperState != .unknown {
                    LabeledContent(vpn.helperState == .ready ? "Remove the helper" : "Set up the helper") {
                        switch vpn.helperState {
                        case .ready: Button("Uninstall…") { confirmingUninstall = true }
                        case .outdated: Button("Update…") { vpn.installHelper() }
                        default: Button("Install…") { vpn.installHelper() }
                        }
                    }
                    .disabled(vpn.helperBusy || vpn.state != .disconnected)
                }
            } header: {
                Text("Helper")
            } footer: {
                Text("The helper is a small system service that runs the VPN with administrator rights, so that connecting does not ask for a password. It is installed the first time you connect.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .autocorrectionDisabled()
        .confirmationDialog("Uninstall the helper?", isPresented: $confirmingUninstall) {
            Button("Uninstall", role: .destructive) { vpn.uninstallHelper() }
        } message: {
            Text("The app cannot connect until the helper is installed again.")
        }
    }
}
