#!/usr/bin/python3
"""Stands in for openconnect in the helper integration test.

It reads the password from standard input like `openconnect --passwd-on-stdin`
and prints what the real program prints. The password selects the behaviour:

    wrong      authentication fails
    stubborn   connects, then ignores SIGINT (only SIGTERM stops it)
    anything   connects, and logs off on SIGINT
"""
import signal
import sys
import time


def say(line):
    print(line, flush=True)


password = sys.stdin.readline().rstrip("\n")
extra = sys.stdin.read()


def log_off(signum, frame):
    say("Logout successful." if signum == signal.SIGINT else "Terminated.")
    sys.exit(0)


signal.signal(signal.SIGTERM, log_off)
signal.signal(signal.SIGINT, signal.SIG_IGN if password == "stubborn" else log_off)

say("ARGUMENTS " + "|".join(sys.argv[1:]))
say("STDIN password-length=%d extra-bytes=%d" % (len(password), len(extra)))
say("POST https://vpn.example.com/global-protect/prelogin.esp")
say("Connected to HTTPS on vpn.example.com with ciphersuite (TLS1.3)-(AES-256-GCM)")
if password == "wrong":
    say("Invalid username or password.")
    say("Failed to complete authentication")
    sys.exit(1)
time.sleep(0.5)
say("ESP session established with server")
say("Configured as 10.20.30.40, with SSL disconnected and ESP established")
while True:
    time.sleep(1)
