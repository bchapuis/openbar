import Foundation

/// Reads the output of openconnect.
public enum OpenConnectOutput {
    /// The tunnel address, if `line` is the one that announces the tunnel.
    ///
    /// openconnect prints "Connected as 10.0.0.1, using SSL..." (version 8) or
    /// "Configured as 10.0.0.1, with SSL..." (version 9). "Connected to HTTPS
    /// on ..." comes earlier and must not match.
    public static func tunnelAddress(in line: String) -> String? {
        line.firstMatch(of: #/^(?:Connected|Configured) as ([0-9A-Fa-f.:]+)/#).map { String($0.1) }
    }

    /// True for the lines the helper adds itself (the command line it ran).
    public static func isCommandEcho(_ line: String) -> Bool {
        line.hasPrefix("$ ")
    }
}

/// Cuts a stream of bytes into lines. Bytes after the last newline are kept
/// until the rest of the line arrives.
public struct LineSplitter: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }
}

/// The most recent log lines. Each line has an index that never changes, so
/// that a reader can ask for "the lines since index n" even after old lines
/// were dropped.
public struct LogBuffer: Sendable {
    public let capacity: Int
    public private(set) var lines: [String] = []
    /// Index of the first line that is still held.
    public private(set) var firstIndex = 0

    public init(capacity: Int = 2000) {
        self.capacity = capacity
    }

    /// Index that the next appended line will get.
    public var endIndex: Int { firstIndex + lines.count }

    public mutating func append(_ line: String) {
        lines.append(line)
        if lines.count > capacity {
            let extra = lines.count - capacity
            lines.removeFirst(extra)
            firstIndex += extra
        }
    }

    /// The lines from index `since` on. An index beyond the end means that the
    /// reader followed an earlier buffer (the helper restarted): it gets everything.
    public func lines(since: Int) -> [String] {
        let from = since > endIndex ? firstIndex : max(since, firstIndex)
        return Array(lines[(from - firstIndex)...])
    }

    /// The last line that says something: what openconnect printed before it stopped.
    public var lastMessage: String? {
        lines.last { !$0.isEmpty && !OpenConnectOutput.isCommandEcho($0) }
    }
}
