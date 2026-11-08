#!/usr/bin/env python3
"""Reject real addresses and WireGuard keys in docs/private-server.md.

A WireGuard key is 32 raw bytes written as standard base64: 43 characters
and one trailing =. Decoding decides that. The word PrivateKey is a separate
finding and is not key material. Placeholders such as <server-vpn-ipv4> and
filenames are allowed.

  python3 tools/private_server_doc.py [FILE]
  python3 tools/private_server_doc.py --self-test
"""
from __future__ import annotations

import argparse
import base64
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs" / "private-server.md"

IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
PRIVATE_KEY_LINE = re.compile(r"(?i)\bprivatekey\b")
# DNS-looking tokens. Filenames and placeholders are skipped below.
HOSTNAME = re.compile(r"\b(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}\b")
FILE_SUFFIX = (".md", ".gd", ".sh", ".py", ".yml", ".json")
_B64 = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")


def _hostname_hits(line: str) -> list[str]:
    hits: list[str] = []
    for m in HOSTNAME.finditer(line):
        token = m.group(0)
        if token.endswith(FILE_SUFFIX):
            continue
        hits.append(token)
    return hits


def _is_wireguard_key(token: str) -> bool:
    """True when token is the canonical standard-base64 form of 32 bytes."""
    try:
        raw = base64.b64decode(token, validate=True)
    except ValueError:
        return False
    return len(raw) == 32 and base64.b64encode(raw).decode("ascii") == token


def _wireguard_keys(line: str) -> list[str]:
    """Base64 runs ended by one =. The = may also be an assignment."""
    found: list[str] = []
    i = 0
    n = len(line)
    while i < n:
        if line[i] not in _B64:
            i += 1
            continue
        j = i + 1
        while j < n and line[j] in _B64:
            j += 1
        end = j + 1 if j < n and line[j] == "=" else j
        token = line[i:end]
        if _is_wireguard_key(token):
            found.append(token)
            i = end
        else:
            # PublicKey=<key> keeps the key after the assignment equals.
            i = j
    return found


def findings(text: str) -> list[str]:
    out: list[str] = []
    for i, line in enumerate(text.splitlines(), 1):
        for m in IPV4.finditer(line):
            out.append(f"{i}: dotted address '{m.group(0)}'")
        if _wireguard_keys(line):
            out.append(f"{i}: key material")
        if PRIVATE_KEY_LINE.search(line):
            out.append(f"{i}: private key field")
        for token in _hostname_hits(line):
            out.append(f"{i}: hostname '{token}'")
    return out


def check_file(path: Path) -> list[str]:
    if not path.is_file():
        return [f"missing {path}"]
    return findings(path.read_text(encoding="utf-8"))


def _material(text: str) -> list[str]:
    return [item for item in findings(text) if item.endswith("key material")]


def _field(text: str) -> list[str]:
    return [item for item in findings(text) if item.endswith("private key field")]


def _synthetic(raw: bytes) -> str:
    if len(raw) != 32:
        raise RuntimeError("synthetic key must be 32 bytes")
    return base64.b64encode(raw).decode("ascii")


def self_test(quiet: bool = False) -> int:
    doc = DOC.read_text(encoding="utf-8")
    errors: list[str] = []
    if findings(doc):
        errors.append("the real doc is not clean: " + "; ".join(findings(doc)))
    zero = _synthetic(b"\x00" * 32)
    seq = _synthetic(bytes(range(32)))
    plus = _synthetic(bytes([0xF8]) + b"\x22" * 31)
    slash = _synthetic(bytes([0xFC]) + b"\x11" * 31)
    if not plus.startswith("+") or not slash.startswith("/"):
        errors.append("synthetic keys did not start with + and /")
    hit = {
        "bare key": zero,
        "end of line": zero + "\n",
        "before whitespace": zero + " next",
        "PublicKey assignment": "PublicKey = " + seq,
        "PublicKey equals": "PublicKey=" + plus + "\n",
        "slash key before space": slash + " ",
    }
    for label, text in hit.items():
        if not _material(text):
            errors.append(f"{label} was accepted")
        if _field(text):
            errors.append(f"{label} was counted as the PrivateKey keyword")
    if not _field("PrivateKey\n") or _material("PrivateKey\n"):
        errors.append("keyword-only line was not kept separate from key material")
    short = ("A" * 42) + "="
    if _material("PrivateKey = " + short + "\n"):
        errors.append("42-character padding was reported as key material")
    if not _field("PrivateKey = " + short):
        errors.append("42-character line lost the keyword finding")
    safe = "Join `<server-vpn-ipv4>`\nSee docker-dedicated-server.md\n"
    if findings(safe):
        errors.append("placeholder or filename was flagged: " + "; ".join(findings(safe)))
    if not any("198.51.100.10" in item for item in findings("Join 198.51.100.10:9786\n")):
        errors.append("planted address was accepted")
    if not any("vpn.example.test" in item for item in findings("Endpoint = vpn.example.test\n")):
        errors.append("planted hostname was accepted")
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / "private-server.md"
        copy.write_text(doc + "\n" + zero + "\n", encoding="utf-8")
        if not any(item.endswith("key material") for item in check_file(copy)):
            errors.append("temp copy with a bare key was accepted")
    if errors:
        print("private-server doc: self-test:", file=sys.stderr)
        for item in errors:
            print(f"  {item}", file=sys.stderr)
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
