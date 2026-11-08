#!/usr/bin/env python3
"""Reject real addresses and keys in docs/private-server.md.

Placeholders such as <server-vpn-ipv4> are allowed. A dotted IPv4 address,
a WireGuard-shaped key, or a Join/Endpoint target that is not a placeholder
is not. The 4.7.2 release notes are not a substitute for this file.

  python3 tools/private_server_doc.py [FILE]
  python3 tools/private_server_doc.py --self-test
"""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs" / "private-server.md"

IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
# WireGuard keys are 32 bytes of base64, with one or two padding equals.
KEY = re.compile(r"\b[A-Za-z0-9+/]{42}={1,2}\b")
PRIVATE_KEY_LINE = re.compile(r"(?i)\bprivatekey\b")
# DNS-looking tokens. Filenames and placeholders are skipped below.
HOSTNAME = re.compile(r"\b(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}\b")
FILE_SUFFIX = (".md", ".gd", ".sh", ".py", ".yml", ".json")


def _hostname_hits(line: str) -> list[str]:
    hits: list[str] = []
    for m in HOSTNAME.finditer(line):
        token = m.group(0)
        if token.endswith(FILE_SUFFIX):
            continue
        hits.append(token)
    return hits


def findings(text: str) -> list[str]:
    out: list[str] = []
    for i, line in enumerate(text.splitlines(), 1):
        for m in IPV4.finditer(line):
            out.append(f"{i}: dotted address '{m.group(0)}'")
        for m in KEY.finditer(line):
            out.append(f"{i}: key material '{m.group(0)}'")
        if PRIVATE_KEY_LINE.search(line):
            out.append(f"{i}: private key field")
        for token in _hostname_hits(line):
            out.append(f"{i}: hostname '{token}'")
    return out


def check_file(path: Path) -> list[str]:
    if not path.is_file():
        return [f"missing {path}"]
    return findings(path.read_text(encoding="utf-8"))


def self_test(quiet: bool = False) -> int:
    doc = DOC.read_text(encoding="utf-8")
    if findings(doc):
        print("private-server doc: self-test: the real doc is not clean:", file=sys.stderr)
        for item in findings(doc):
            print(f"  {item}", file=sys.stderr)
        return 1
    planted = (
        doc
        + "\nJoin 198.51.100.10:9786\n"
        + "Endpoint = vpn.example.test\n"
        + "PrivateKey = " + ("A" * 42) + "=\n"
    )
    bad = findings(planted)
    if not any("198.51.100.10" in item for item in bad):
        print("private-server doc: self-test: planted address was accepted", file=sys.stderr)
        return 1
    if not any("key" in item.lower() for item in bad):
        print("private-server doc: self-test: planted key was accepted", file=sys.stderr)
        return 1
    if not any("vpn.example.test" in item for item in bad):
        print("private-server doc: self-test: planted hostname was accepted", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / "private-server.md"
        copy.write_text(planted, encoding="utf-8")
        if not check_file(copy):
            print("private-server doc: self-test: temp copy was accepted", file=sys.stderr)
            return 1
    if not quiet:
        print("private-server doc: self-test ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("path", nargs="?", default=str(DOC))
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    found = check_file(Path(args.path))
    if found:
        print(f"private-server doc: {len(found)} problem(s) in {args.path}", file=sys.stderr)
        for item in found:
            print(f"  {item}", file=sys.stderr)
        return 1
    print(f"private-server doc: ok {args.path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
