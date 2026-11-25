import SwiftUI

extension VPNController {
    /// The color that stands for the current state.
    var tint: Color {
        if helperBusy { return .orange }
        switch state {
        case .disconnected: return .gray
        case .connecting, .disconnecting: return .orange
        case .connected: return .green
        }
    }
}

/// The state icon in a tinted circle.
struct StatusBadge: View {
    @EnvironmentObject private var vpn: VPNController
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: vpn.symbolName)
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundStyle(vpn.tint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, isActive: vpn.isBusy)
            .frame(width: size, height: size)
            .background(vpn.tint.opacity(0.16), in: Circle())
            .animation(.smooth, value: vpn.symbolName)
            .accessibilityHidden(true)
    }
}

/// One line under the status title: what the VPN is doing, or what went wrong.
struct StatusDetail: View {
    @EnvironmentObject private var vpn: VPNController
    @AppStorage(SettingsKey.server) private var server = ""
    /// Short texts, for the menu bar panel.
    var compact = false

    var body: some View {
        Group {
            if vpn.helperBusy {
                Text("Waiting for your administrator password")
            } else if vpn.helperState == .unknown {
                Text("Looking for the helper")
            } else if vpn.state == .connected {
                HStack(spacing: 4) {
                    if let address = vpn.address {
                        Text(address)
                        Text("·")
                    }
                    if let since = vpn.connectedSince {
                        Text(since, style: .timer).monospacedDigit()
                    }
                }
            } else if vpn.state == .connecting {
                Text(compact ? server : "Contacting \(server)")
            } else if vpn.state == .disconnecting {
                Text("Logging off")
            } else if let error = vpn.errorMessage {
                Text(error).foregroundStyle(.red)
            } else if server.isEmpty {
                Text("No server configured")
            } else if vpn.needsHelperInstall, !compact {
                Text("The first connection installs a helper and asks for your administrator password once.")
            } else {
                Text(server)
            }
        }
        .foregroundStyle(.secondary)
        .lineLimit(compact ? 2 : 3)
    }
}
