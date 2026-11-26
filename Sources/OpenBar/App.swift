import AppKit
import SwiftUI

struct OpenBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var vpn = VPNController.shared
    @StateObject private var navigation = Navigation()

    init() {
        Settings.registerDefaults()
    }

    /// The menu bar ignores SwiftUI font modifiers on its label, and a shield
    /// drawn at the default size looks small next to other menu bar icons.
    /// Render the symbol at an explicit size instead.
    ///
    /// The menu bar sizes its item from the label image and does not always
    /// resize it when the image changes, so a symbol bigger than the one shown
    /// before gets clipped. Draw every symbol centered on one canvas that fits
    /// them all, so the item's size never changes.
    private static func menuBarImage(_ symbolName: String) -> NSImage {
        let symbol = menuBarSymbol(symbolName)
        let canvas = menuBarCanvas
        let image = NSImage(size: canvas, flipped: false) { rect in
            let origin = NSPoint(x: (rect.width - symbol.size.width) / 2,
                                 y: (rect.height - symbol.size.height) / 2)
            symbol.draw(in: NSRect(origin: origin, size: symbol.size))
            return true
        }
        // Template images follow the menu bar's light or dark appearance.
        image.isTemplate = true
        return image
    }

    private static func menuBarSymbol(_ symbolName: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
    }

    /// The smallest size that holds every symbol the menu bar can show.
    private static let menuBarCanvas: NSSize = VPNController.allSymbolNames
        .map { menuBarSymbol($0).size }
        .reduce(NSSize.zero) { NSSize(width: max($0.width, $1.width), height: max($0.height, $1.height)) }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environmentObject(vpn)
                .environmentObject(navigation)
        } label: {
            MenuBarLabel(image: Self.menuBarImage(vpn.symbolName), status: vpn.statusText)
        }
        .menuBarExtraStyle(.window)

        Window("OpenBar", id: "main") {
            MainView()
                .environmentObject(vpn)
                .environmentObject(navigation)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 480, height: 640)
        // Only show the window at launch when there is nothing configured yet.
        .defaultLaunchBehavior(Settings.load().isConfigured ? .suppressed : .presented)
    }
}

/// The menu bar icon. It always exists, so it is also where the app delegate
/// gets the SwiftUI action that opens the main window.
private struct MenuBarLabel: View {
    let image: NSImage
    let status: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = AppDelegate.showMainWindow = { [openWindow] in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Image(nsImage: image)
            .accessibilityLabel("OpenBar: \(status)")
    }
}

/// Which tab the main window shows. Shared so the menu bar panel can open
/// the window on a given tab.
@MainActor
final class Navigation: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case connection = "Connection"
        case advanced = "Advanced"
        case logs = "Logs"

        var id: String { rawValue }
    }

    @Published var tab = Tab.connection
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opens the main window. Set by the menu bar label.
    @MainActor static var showMainWindow: () -> Void = {}

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app while it is already running (Spotlight, Finder, `open`)
    /// shows the window; a menu bar app would otherwise seem to do nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Self.showMainWindow()
        return false
    }

    /// Disconnect the VPN before quitting so routes and DNS are restored.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let vpn = VPNController.shared
        guard vpn.needsShutdown else { return .terminateNow }
        Task { @MainActor in
            await vpn.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
