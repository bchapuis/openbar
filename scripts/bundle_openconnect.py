#!/usr/bin/env python3
"""Copies Homebrew's openconnect into a relocatable directory.

Usage: bundle_openconnect.py <output-dir>

The result does not depend on Homebrew at run time:
    bin/openconnect       the binary, with library paths rewritten
    lib/*.dylib           every non-system library it needs, recursively
    libexec/hipreport.sh  GlobalProtect HIP report script
    etc/vpnc-script       sets routes and DNS
    etc/cert.pem          certificate authorities used to verify the server
"""
import os
import shutil
import subprocess
import sys


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def dependencies(path):
    """Library references of a Mach-O file, without its own install name."""
    lines = run("otool", "-L", path).splitlines()[1:]
    refs = [line.split()[0] for line in lines if line.strip()]
    own = run("otool", "-D", path).splitlines()[1:]
    return [r for r in refs if r not in own]


def is_system(ref):
    return ref.startswith(("/usr/lib/", "/System/"))


def resolve(ref, source):
    """Absolute path of a reference found in the original file `source`."""
    for prefix in ("@loader_path/", "@rpath/"):
        if ref.startswith(prefix):
            return os.path.join(os.path.dirname(source), ref[len(prefix):])
    return ref


# Fixes for the upstream vpnc-script on current macOS, as (original, replacement).
# Each original must appear exactly once, so an upstream change fails the build
# instead of silently shipping an unpatched script.
VPNC_SCRIPT_PATCHES = [
    # Keep the networksetup DNS backup next to the other per-connection files.
    (
        "RESOLV_CONF_BACKUP=/var/run/vpnc/resolv.conf-backup.${VPNPID}\n",
        "RESOLV_CONF_BACKUP=/var/run/vpnc/resolv.conf-backup.${VPNPID}\n"
        "NETWORKSETUP_BACKUP=/var/run/vpnc/networksetup-backup.${VPNPID}\n",
    ),
    # IPv6 default gateway. macOS already prints link-local gateways with their
    # scope ("fe80::1%en0"), so appending "%iface" again gives "fe80::1%en0%en0".
    # It also lists interface-scoped defaults (flag "I", e.g. one per utun from
    # iCloud Private Relay); printing all of them makes a multi-line "gateway".
    # Print only the first unscoped default, with its scope added once.
    (
        "\t\tnetstat -r -n $netstat_syntax_ipv6 | awk '/^(default|::\\/0)/ { if ($NF!~/^lo/ && $NF!~/'\"$TUNDEV\"'([[:space:]]|$)/) { print ($2~/^fe[89ab]/ ? $2\"%\"$NF : $2); } }'\n",
        "\t\tnetstat -r -n $netstat_syntax_ipv6 | awk '/^(default|::\\/0)/ { if ($NF!~/^lo/ && $NF!~/'\"$TUNDEV\"'([[:space:]]|$)/ && $3!~/I/) { gw=$2; if (gw~/^fe[89ab]/ && gw!~/%/) gw=gw\"%\"$NF; print gw; exit; } }'\n",
    ),
    # DNS on connect. The default route already points at the tunnel here, so
    # "route get default" names the utun device, no network service matches,
    # and networksetup fails ("is not a recognized network service"). Use the
    # interface that carries the route to the VPN gateway instead, and save the
    # service's DNS servers so that disconnecting puts them back.
    (
        "\t\t\t\tACTIVE_INTERFACE=`route -n get default | grep interface | awk '{print $2}'`\n"
        "\t\t\t\tACTIVE_NETWORK_SERVICE=`networksetup -listnetworkserviceorder | grep -B 1 \"$ACTIVE_INTERFACE\" | head -n 1 | awk '/\\([0-9]+\\)/{ print }'|cut -d \" \" -f2-`\n"
        "\t\t\t\tnetworksetup -setdnsservers \"$ACTIVE_NETWORK_SERVICE\" $INTERNAL_IP4_DNS\n",
        "\t\t\t\tACTIVE_INTERFACE=`route -n get \"$VPNGATEWAY\" | awk '/interface:/ { print $2 }'`\n"
        "\t\t\t\tACTIVE_NETWORK_SERVICE=`networksetup -listnetworkserviceorder | grep -B 1 \"Device: $ACTIVE_INTERFACE)\" | head -n 1 | awk '/\\([0-9]+\\)/{ print }'|cut -d \" \" -f2-`\n"
        "\t\t\t\tif [ -n \"$ACTIVE_INTERFACE\" ] && [ -n \"$ACTIVE_NETWORK_SERVICE\" ]; then\n"
        "\t\t\t\t\tPREVIOUS_DNS=`networksetup -getdnsservers \"$ACTIVE_NETWORK_SERVICE\" | grep -E '^[0-9a-fA-F.:]+$' | xargs`\n"
        "\t\t\t\t\tprintf '%s\\n%s\\n' \"$ACTIVE_NETWORK_SERVICE\" \"${PREVIOUS_DNS:-Empty}\" > \"$NETWORKSETUP_BACKUP\"\n"
        "\t\t\t\t\tnetworksetup -setdnsservers \"$ACTIVE_NETWORK_SERVICE\" $INTERNAL_IP4_DNS\n"
        "\t\t\t\tfi\n",
    ),
    # DNS on disconnect. Upstream looks the service up again and sets its DNS
    # to "Empty", which also wipes DNS servers the user configured by hand.
    # Restore what was saved on connect instead, and only if anything was.
    (
        "\t\t\t\tACTIVE_INTERFACE=`route -n get default | grep interface | awk '{print $2}'`\n"
        "\t\t\t\tACTIVE_NETWORK_SERVICE=`networksetup -listnetworkserviceorder | grep -B 1 \"$ACTIVE_INTERFACE\" | head -n 1 | awk '/\\([0-9]+\\)/{ print }'|cut -d \" \" -f2-`\n"
        "\t\t\t\tnetworksetup -setdnsservers \"$ACTIVE_NETWORK_SERVICE\" Empty\n",
        "\t\t\t\tif [ -s \"$NETWORKSETUP_BACKUP\" ]; then\n"
        "\t\t\t\t\tACTIVE_NETWORK_SERVICE=`sed -n 1p \"$NETWORKSETUP_BACKUP\"`\n"
        "\t\t\t\t\tPREVIOUS_DNS=`sed -n 2p \"$NETWORKSETUP_BACKUP\"`\n"
        "\t\t\t\t\tnetworksetup -setdnsservers \"$ACTIVE_NETWORK_SERVICE\" $PREVIOUS_DNS\n"
        "\t\t\t\t\trm -f -- \"$NETWORKSETUP_BACKUP\"\n"
        "\t\t\t\tfi\n",
    ),
]


def patch_vpnc_script(source, target):
    with open(source) as f:
        script = f.read()
    for original, replacement in VPNC_SCRIPT_PATCHES:
        count = script.count(original)
        if count != 1:
            sys.exit(f"vpnc-script: expected one match for a patch, found {count}:\n{original}")
        script = script.replace(original, replacement)
    with open(target, "w") as f:
        f.write(script)
    os.chmod(target, 0o755)


def main():
    out = os.path.abspath(sys.argv[1])
    prefix = run("brew", "--prefix").strip()
    oc_prefix = os.path.realpath(run("brew", "--prefix", "openconnect").strip())

    shutil.rmtree(out, ignore_errors=True)
    for sub in ("bin", "lib", "libexec", "etc"):
        os.makedirs(os.path.join(out, sub))

    binary = os.path.join(out, "bin", "openconnect")
    shutil.copy(os.path.join(oc_prefix, "bin", "openconnect"), binary)

    # (copied file, original file it came from)
    queue = [(binary, os.path.join(oc_prefix, "bin", "openconnect"))]
    seen = set()
    while queue:
        copy, source = queue.pop()
        os.chmod(copy, 0o755)
        in_lib = os.path.dirname(copy).endswith("/lib")
        if in_lib:
            run("install_name_tool", "-id", "@loader_path/" + os.path.basename(copy), copy)
        for ref in dependencies(copy):
            if is_system(ref):
                continue
            original = os.path.realpath(resolve(ref, source))
            name = os.path.basename(ref)
            target = os.path.join(out, "lib", name)
            if name not in seen:
                seen.add(name)
                shutil.copy(original, target)
                queue.append((target, original))
            new_ref = ("@loader_path/" if in_lib else "@loader_path/../lib/") + name
            run("install_name_tool", "-change", ref, new_ref, copy)

    shutil.copy(os.path.join(oc_prefix, "libexec", "openconnect", "hipreport.sh"),
                os.path.join(out, "libexec", "hipreport.sh"))
    patch_vpnc_script(os.path.join(prefix, "etc", "vpnc", "vpnc-script"),
                      os.path.join(out, "etc", "vpnc-script"))
    shutil.copy(os.path.realpath(os.path.join(prefix, "etc", "ca-certificates", "cert.pem")),
                os.path.join(out, "etc", "cert.pem"))

    # Rewriting the load commands invalidates the signatures; arm64 refuses
    # to run unsigned code, so sign everything again (ad hoc).
    machos = [binary] + [os.path.join(out, "lib", f) for f in sorted(os.listdir(os.path.join(out, "lib")))]
    for path in machos:
        run("codesign", "--force", "--sign", "-", path)
        leftovers = [r for r in dependencies(path) if not is_system(r) and not r.startswith("@loader_path/")]
        if leftovers:
            sys.exit(f"{path} still references {leftovers}")

    print(f"Bundled openconnect with {len(machos) - 1} libraries into {out}")


if __name__ == "__main__":
    main()
