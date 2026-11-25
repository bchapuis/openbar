import Testing
@testable import HelperShared

@Suite struct ConnectionRequestValidation {
    private func request(server: String = "vpn.example.com", user: String = "alex@example.com",
                         vpnProtocol: String = "gp", options: [String] = []) -> ConnectionRequest {
        ConnectionRequest(server: server, user: user, vpnProtocol: vpnProtocol, options: options)
    }

    @Test func acceptsAnOrdinaryRequest() {
        #expect(request().validationError(password: "secret") == nil)
    }

    @Test(arguments: ["vpn.example.com", "vpn.example.com:8443", "vpn.example.com/gateway", "10.0.0.1", "vpn-2.example.com:443/a/b"])
    func acceptsServer(_ server: String) {
        #expect(request(server: server).validationError(password: "secret") == nil)
    }

    // A server that starts with "-" would be read by openconnect as an option;
    // the others could carry shell or URL tricks.
    @Test(arguments: ["", "-vpn.example.com", "--script=/tmp/evil", "vpn.example.com --script=x",
                      "vpn.example.com;id", "$(id)", "vpn.example.com\n", "https://vpn.example.com"])
    func rejectsServer(_ server: String) {
        #expect(request(server: server).validationError(password: "secret") == "Invalid server name.")
    }

    @Test func rejectsAnEmptyOrMultilineUser() {
        #expect(request(user: "").validationError(password: "secret") == "Invalid user name.")
        #expect(request(user: "alex\nroot").validationError(password: "secret") == "Invalid user name.")
    }

    @Test func rejectsAnUnknownProtocol() {
        #expect(request(vpnProtocol: "gp --script=x").validationError(password: "secret") == "Invalid protocol.")
        #expect(request(vpnProtocol: "").validationError(password: "secret") == "Invalid protocol.")
    }

    @Test(arguments: HelperConstants.protocols)
    func acceptsEveryListedProtocol(_ name: String) {
        #expect(request(vpnProtocol: name).validationError(password: "secret") == nil)
    }

    // The password is one line on openconnect's standard input: a second line
    // would be read as the answer to the next prompt.
    @Test func rejectsAnEmptyOrMultilinePassword() {
        #expect(request().validationError(password: "") == "Invalid password.")
        #expect(request().validationError(password: "secret\nmore") == "Invalid password.")
    }

    @Test(arguments: ["--servercert=pin-sha256:abc", "--authgroup=staff", "--no-dtls", "--mtu=1300", "--os=mac-intel"])
    func acceptsAllowedOption(_ option: String) {
        #expect(request(options: [option]).validationError(password: "secret") == nil)
    }

    // These would let an unprivileged client run a program or read a file as root.
    @Test(arguments: ["--script=/tmp/evil.sh", "--csd-wrapper=/tmp/evil.sh", "--config=/etc/master.passwd",
                      "--cafile=/tmp/ca.pem", "--background", "-s", "/tmp/evil.sh", ""])
    func rejectsOtherOption(_ option: String) {
        #expect(request(options: [option]).validationError(password: "secret") == "Option not allowed: \(option)")
    }

    @Test func oneBadOptionRejectsTheRequest() {
        let error = request(options: ["--no-dtls", "--script=/tmp/evil.sh"]).validationError(password: "secret")
        #expect(error == "Option not allowed: --script=/tmp/evil.sh")
    }
}

@Suite struct ConnectionRequestArguments {
    private let bundle = "/Library/Application Support/OpenBar/openconnect"

    @Test func buildsTheFullCommandLine() {
        let request = ConnectionRequest(server: "vpn.example.com", user: "alex@example.com", vpnProtocol: "gp",
                                        disableIPv6: true, hipReport: true, options: ["--no-dtls"])
        #expect(request.arguments(bundle: bundle) == [
            "--protocol=gp",
            "--user=alex@example.com",
            "--disable-ipv6",
            "--csd-wrapper=\(bundle)/libexec/hipreport.sh",
            "--script='\(bundle)/etc/vpnc-script'",
            "--no-system-trust",
            "--cafile=\(bundle)/etc/cert.pem",
            "--no-dtls",
            "--passwd-on-stdin",
            "--non-inter",
            "vpn.example.com",
        ])
    }

    @Test func leavesOutWhatIsSwitchedOff() {
        let arguments = ConnectionRequest(server: "vpn.example.com", user: "alex", vpnProtocol: "anyconnect")
            .arguments(bundle: bundle)
        #expect(!arguments.contains("--disable-ipv6"))
        #expect(!arguments.contains { $0.hasPrefix("--csd-wrapper=") })
    }

    // Regression: openconnect runs --script through /bin/sh. Without quotes the
    // space in "Application Support" split the path, the script failed with
    // error 127, and the tunnel came up without routes or DNS.
    @Test func quotesTheScriptPathForTheShell() {
        let arguments = ConnectionRequest(server: "vpn.example.com", user: "alex", vpnProtocol: "gp")
            .arguments(bundle: bundle)
        #expect(arguments.contains("--script='/Library/Application Support/OpenBar/openconnect/etc/vpnc-script'"))
    }

    @Test func theServerComesLast() {
        let arguments = ConnectionRequest(server: "vpn.example.com", user: "alex", vpnProtocol: "gp",
                                          options: ["--no-dtls"]).arguments(bundle: bundle)
        #expect(arguments.last == "vpn.example.com")
    }

    @Test func neverPutsThePasswordOnTheCommandLine() {
        let arguments = ConnectionRequest(server: "vpn.example.com", user: "alex", vpnProtocol: "gp")
            .arguments(bundle: bundle)
        #expect(arguments.contains("--passwd-on-stdin"))
        #expect(!arguments.contains { $0.hasPrefix("--password") })
    }
}

@Suite struct ShellQuoting {
    @Test func wrapsInSingleQuotes() {
        #expect(Shell.quote("/a path/with spaces") == "'/a path/with spaces'")
    }

    @Test func escapesSingleQuotes() {
        #expect(Shell.quote("it's") == "'it'\\''s'")
    }

    @Test func keepsShellCharactersLiteral() {
        #expect(Shell.quote("$(id); `id` \"x\"") == "'$(id); `id` \"x\"'")
    }

    @Test func quotesTheEmptyString() {
        #expect(Shell.quote("") == "''")
    }
}
