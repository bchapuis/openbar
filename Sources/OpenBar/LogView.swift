import AppKit
import SwiftUI

/// The openconnect output, with a filter.
struct LogTab: View {
    @EnvironmentObject private var vpn: VPNController
    @State private var filter = ""

    private var lines: [String] {
        filter.isEmpty ? vpn.log : vpn.log.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        let lines = lines
        VStack(spacing: 8) {
            Group {
                if lines.isEmpty {
                    ContentUnavailableView(
                        vpn.log.isEmpty ? "No Logs Yet" : "No Matching Lines",
                        systemImage: "text.alignleft",
                        description: Text(vpn.log.isEmpty ? "The output of openconnect appears here." : "")
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(Self.styled(lines))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                            Color.clear.frame(height: 1).id("end")
                        }
                        .onChange(of: vpn.log.count) { proxy.scrollTo("end") }
                        .onAppear { proxy.scrollTo("end") }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))

            HStack {
                TextField("Filter", text: $filter, prompt: Text("Filter"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                Text("\(lines.count) lines")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                }
                Button("Clear") { vpn.clearLog() }
            }
            .disabled(vpn.log.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    /// One attributed string, so that the selection can span lines.
    private static func styled(_ lines: [String]) -> AttributedString {
        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            var part = AttributedString(index == lines.count - 1 ? line : line + "\n")
            part.foregroundColor = color(of: line)
            result.append(part)
        }
        return result
    }

    private static func color(of line: String) -> Color {
        let lower = line.lowercased()
        if line.hasPrefix("$ ") { return .secondary }
        if lower.contains("fail") || lower.contains("error") || lower.contains("invalid") { return .red }
        if lower.hasPrefix("configured as") || lower.hasPrefix("connected as")
            || lower.contains("session established") { return .green }
        return .primary
    }
}
