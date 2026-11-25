import AppKit
import SwiftUI

/// The panel that opens from the menu bar icon.
struct MenuPanel: View {
    @EnvironmentObject private var vpn: VPNController
    @EnvironmentObject private var navigation: Navigation
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.user) private var user = ""

    /// The switch reflects the VPN and drives it.
    private var isOn: Binding<Bool> {
        Binding {
            vpn.isOn
        } set: { on in
            if !on {
                vpn.disconnect()
            } else if vpn.password.isEmpty || !Settings.load().isConfigured {
                // The window is needed to type the missing settings.
                show(.connection)
            } else {
                vpn.connect()
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                StatusBadge(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(vpn.title).font(.headline)
                    StatusDetail(compact: true).font(.subheadline)
                }
                Spacer(minLength: 8)
                Toggle("VPN", isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!vpn.canConnect && !vpn.canDisconnect)
            }
            .padding(12)

            if vpn.state == .connected, !user.isEmpty {
                Divider().padding(.horizontal, 12)
                LabeledContent("Account", value: user)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }

            Divider().padding(.horizontal, 12)

            VStack(spacing: 0) {
                MenuRow("Settings…", systemImage: "gearshape") { show(.connection) }
                MenuRow("Logs…", systemImage: "text.alignleft") { show(.logs) }
                Divider().padding(.horizontal, 6).padding(.vertical, 4)
                MenuRow("Quit OpenBar", systemImage: "power", shortcut: "⌘Q") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(6)
        }
        .frame(width: 300)
    }

    private func show(_ tab: Navigation.Tab) {
        navigation.tab = tab
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A row that looks and behaves like a menu item.
private struct MenuRow: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, systemImage: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 18)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(hovering ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(hovering ? .white : .primary)
            .background(hovering ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
