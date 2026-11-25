import AppKit
import SwiftUI

/// `OpenBar --snapshot <directory>` renders the views to PNG files in
/// their current state and exits. A development aid for checking the layout
/// without clicking through the app.
@MainActor
enum Snapshot {
    static func run(directory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let vpn = VPNController.shared

        var hosts: [(String, NSView, NSWindow)] = []
        func add(_ name: String, _ view: some View, size: CGSize? = nil) {
            let host = NSHostingView(rootView: view.environmentObject(vpn))
            // The panel has no title bar; the window hides its own.
            let style: NSWindow.StyleMask = size == nil ? [.borderless] : [.titled, .fullSizeContentView]
            let size = size ?? host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                                  styleMask: style, backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = host
            window.orderFront(nil)
            hosts.append((name, host, window))
        }

        add("panel", MenuPanel().environmentObject(Navigation()))
        for tab in Navigation.Tab.allCases {
            let navigation = Navigation()
            navigation.tab = tab
            add("window-\(tab.rawValue.lowercased())", MainView().environmentObject(navigation),
                size: CGSize(width: 480, height: 640))
        }

        // Leave time for the helper to answer and for the views to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            for (name, host, window) in hosts {
                if name == "panel" { window.setContentSize(host.fittingSize) }
                window.displayIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
            }
            exit(0)
        }
        app.run()
    }
}
