#!/usr/bin/env python3
"""Check the architecture slices of the dylibs inside a built .deb.

Why this exists
---------------
On an A12 or newer device SpringBoard runs as arm64e, so a release build needs an
arm64e slice. But there are two arm64e ABIs:

    cpusubtype 0x00000002   pre-iOS-14 ABI      iOS 15+ refuses to load it
    cpusubtype 0x80000002   iOS 14+ ABI         what we need

and dyld *prefers* the arm64e slice over the arm64 one. So a dylib carrying an
old-ABI arm64e slice does not fall back gracefully — it fails to load at all.

Theos on Linux can only emit the old ABI (the new one lives in Apple's closed Xcode
clang), which is why Linux builds here are deliberately arm64-only and releases are
built on macOS. This script is the guard that stops a broken slice reaching a device.

Usage:
    tools/check-slices.py packages/*.deb          # audit
    tools/check-slices.py --require-arm64e ...    # also demand a good arm64e slice
"""

import argparse
import glob
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

FAT_MAGICS = (0xCAFEBABE, 0xCAFEBABF)
MH_MAGIC_64 = 0xFEEDFACF

CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64_ALL = 0x00000000
CPU_SUBTYPE_ARM64E = 0x00000002
CPU_SUBTYPE_PTRAUTH_ABI = 0x80000000


def describe(cpu_type: int, cpu_subtype: int) -> str:
    if cpu_type != CPU_TYPE_ARM64:
        return f"cputype {cpu_type:#x} subtype {cpu_subtype:#010x}"
    masked = cpu_subtype & ~CPU_SUBTYPE_PTRAUTH_ABI & 0x00FFFFFF
    if masked == CPU_SUBTYPE_ARM64_ALL:
        return "arm64"
    if masked == CPU_SUBTYPE_ARM64E:
        if cpu_subtype & CPU_SUBTYPE_PTRAUTH_ABI:
            return f"arm64e (iOS 14+ ABI, ptrauth v{(cpu_subtype >> 24) & 0x7F})"
        return "arm64e (PRE-iOS-14 ABI — will not load on iOS 15+)"
    return f"cputype {cpu_type:#x} subtype {cpu_subtype:#010x}"


def read_slices(path: Path):
    """Return [(cpu_type, cpu_subtype)] for a Mach-O, fat or thin."""
    with path.open("rb") as handle:
        head = handle.read(4096)
    if len(head) < 8:
        return []

    if struct.unpack(">I", head[:4])[0] in FAT_MAGICS:
        count = struct.unpack(">I", head[4:8])[0]
        out = []
        for i in range(min(count, 16)):
            offset = 8 + i * 20
            cpu_type, cpu_subtype = struct.unpack(">ii", head[offset:offset + 8])
            out.append((cpu_type & 0xFFFFFFFF, cpu_subtype & 0xFFFFFFFF))
        return out

    for endian in ("<", ">"):
        if struct.unpack(endian + "I", head[:4])[0] == MH_MAGIC_64:
            cpu_type, cpu_subtype = struct.unpack(endian + "ii", head[4:12])
            return [(cpu_type & 0xFFFFFFFF, cpu_subtype & 0xFFFFFFFF)]
    return []


def check_deb(deb: Path, require_arm64e: bool) -> bool:
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["dpkg-deb", "-x", str(deb), tmp], check=True)
        machos = [
            p for p in Path(tmp).rglob("*")
            if p.is_file() and read_slices(p)
        ]
        if not machos:
            print(f"{deb.name}: no Mach-O binaries found", file=sys.stderr)
            return False

        print(f"\n{deb.name}")
        for macho in sorted(machos):
            slices = read_slices(macho)
            rel = str(macho.relative_to(tmp))
            names = [describe(*s) for s in slices]
            print(f"  {rel}")
            for name in names:
                print(f"      {name}")

            for cpu_type, cpu_subtype in slices:
                is_arm64e = (cpu_type == CPU_TYPE_ARM64
                             and (cpu_subtype & 0x00FFFFFF) == CPU_SUBTYPE_ARM64E)
                if is_arm64e and not (cpu_subtype & CPU_SUBTYPE_PTRAUTH_ABI):
                    print(f"      FAIL: old-ABI arm64e slice; iOS 15+ will refuse to "
                          f"load this dylib entirely", file=sys.stderr)
                    ok = False

            if require_arm64e:
                has_good_arm64e = any(
                    cpu_type == CPU_TYPE_ARM64
                    and (cpu_subtype & 0x00FFFFFF) == CPU_SUBTYPE_ARM64E
                    and (cpu_subtype & CPU_SUBTYPE_PTRAUTH_ABI)
                    for cpu_type, cpu_subtype in slices
                )
                if not has_good_arm64e:
                    print("      FAIL: no iOS 14+ ABI arm64e slice; this will not "
                          "inject into SpringBoard on A12 or newer", file=sys.stderr)
                    ok = False
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("debs", nargs="+", help=".deb files (globs accepted)")
    parser.add_argument("--require-arm64e", action="store_true",
                        help="fail unless a correct arm64e slice is present "
                             "(use for release builds)")
    args = parser.parse_args()

    if not shutil.which("dpkg-deb"):
        print("dpkg-deb not found", file=sys.stderr)
        return 2

    paths = [Path(p) for pattern in args.debs for p in glob.glob(pattern)]
    if not paths:
        print("no .deb files matched", file=sys.stderr)
        return 2

    ok = all(check_deb(path, args.require_arm64e) for path in paths)
    print("\nOK" if ok else "\nFAILED", file=sys.stderr if not ok else sys.stdout)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
