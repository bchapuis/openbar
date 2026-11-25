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
    shutil.copy(os.path.join(prefix, "etc", "vpnc", "vpnc-script"),
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
