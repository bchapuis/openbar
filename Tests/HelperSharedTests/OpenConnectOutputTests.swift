import Foundation
import Testing
@testable import HelperShared

@Suite struct TunnelAddress {
    @Test func readsTheVersion9Line() {
        let line = "Configured as 10.193.24.245, with SSL disconnected and ESP established"
        #expect(OpenConnectOutput.tunnelAddress(in: line) == "10.193.24.245")
    }

    @Test func readsTheVersion8Line() {
        let line = "Connected as 10.0.0.7, using SSL, with ESP in progress"
        #expect(OpenConnectOutput.tunnelAddress(in: line) == "10.0.0.7")
    }

    @Test func readsAnIPv6Address() {
        #expect(OpenConnectOutput.tunnelAddress(in: "Configured as fd00::1:2, with SSL connected") == "fd00::1:2")
    }

    // These lines appear before the tunnel is up and must not count as "connected".
    @Test(arguments: [
        "Connected to HTTPS on vpn.example.com with ciphersuite (TLS1.3)-(AES-256-GCM)",
        "Connected to 203.0.113.10:443",
        "ESP session established with server",
        "  Configured as 10.0.0.1, with SSL connected",
        "",
    ])
    func ignores(_ line: String) {
        #expect(OpenConnectOutput.tunnelAddress(in: line) == nil)
    }

    @Test func recognisesTheCommandEcho() {
        #expect(OpenConnectOutput.isCommandEcho("$ openconnect --protocol=gp vpn.example.com"))
        #expect(!OpenConnectOutput.isCommandEcho("POST https://vpn.example.com/"))
    }
}

@Suite struct LineSplitting {
    @Test func splitsCompleteLines() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("one\ntwo\n".utf8)) == ["one", "two"])
    }

    @Test func keepsAPartialLineUntilItIsComplete() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("Configured as 10.".utf8)) == [])
        #expect(splitter.append(Data("0.0.1, with SSL\nnext".utf8)) == ["Configured as 10.0.0.1, with SSL"])
        #expect(splitter.append(Data("\n".utf8)) == ["next"])
    }

    @Test func keepsEmptyLines() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("a\n\nb\n".utf8)) == ["a", "", "b"])
    }

    @Test func survivesInvalidUTF8() {
        var splitter = LineSplitter()
        let lines = splitter.append(Data([0x61, 0xFF, 0x62, 0x0A]))
        #expect(lines.count == 1)
        #expect(lines[0].hasPrefix("a") && lines[0].hasSuffix("b"))
    }
}

@Suite struct LogBuffering {
    private func buffer(_ lines: [String], capacity: Int = 2000) -> LogBuffer {
        var buffer = LogBuffer(capacity: capacity)
        lines.forEach { buffer.append($0) }
        return buffer
    }

    @Test func startsEmpty() {
        let buffer = LogBuffer()
        #expect(buffer.lines(since: 0) == [])
        #expect(buffer.endIndex == 0)
        #expect(buffer.lastMessage == nil)
    }

    @Test func returnsOnlyTheNewLines() {
        let buffer = buffer(["a", "b", "c"])
        #expect(buffer.lines(since: 0) == ["a", "b", "c"])
        #expect(buffer.lines(since: 2) == ["c"])
        #expect(buffer.lines(since: 3) == [])
        #expect(buffer.endIndex == 3)
    }

    @Test func dropsTheOldestLinesButKeepsTheirIndices() {
        let buffer = buffer(["a", "b", "c", "d", "e"], capacity: 3)
        #expect(buffer.lines == ["c", "d", "e"])
        #expect(buffer.firstIndex == 2)
        #expect(buffer.endIndex == 5)
        // A reader that was at index 4 gets exactly the line it has not seen.
        #expect(buffer.lines(since: 4) == ["e"])
        // A reader that fell behind gets what is left.
        #expect(buffer.lines(since: 0) == ["c", "d", "e"])
    }

    // After a restart the helper's buffer is new and shorter than what the
    // app last saw; the app must receive it from the start.
    @Test func sendsEverythingToAReaderFromAnEarlierBuffer() {
        let buffer = buffer(["a", "b"])
        #expect(buffer.lines(since: 500) == ["a", "b"])
    }

    @Test func toleratesANegativeIndex() {
        #expect(buffer(["a"]).lines(since: -5) == ["a"])
    }

    @Test func lastMessageSkipsBlankLinesAndTheCommandEcho() {
        #expect(buffer(["$ openconnect vpn.example.com", "Failed to complete authentication", ""]).lastMessage
            == "Failed to complete authentication")
        #expect(buffer(["$ openconnect vpn.example.com"]).lastMessage == nil)
    }
}
