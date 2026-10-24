#!/usr/bin/env python3
"""Pull request hygiene check: the privacy rule and the size rule from AGENTS.md.

Hard failures (exit 1), kept to cases that are almost never false positives:
  * an email address in the PR title, PR body, a commit message, or an added
    diff line (GitHub noreply addresses, reserved example domains and
    allowlisted addresses are fine);
  * an absolute local path: a home directory under /home or /Users, a Windows
    user-profile path, or a path under the /workspace scratch root;
  * more than CAP counted code lines without a justification in the PR body
    (a "## Why this is large" section or a "Size justification:" line).

Warnings only (shown as annotations and in the job summary, never blocking):
  * attribution phrases such as "<someone> says" or "the owner <verb>";
  * the PR author's login appearing in the text (the repository slug and
    GitHub URLs are ignored);
  * no "Size:" line in the PR body.

Git author metadata (author and committer name/email) is not scanned.

Escape hatch: .github/pr-hygiene-allow.txt. One entry per line, "#" starts a
comment:
  <text>               ignore a finding whose matched text equals <text>
                       (case-insensitive), for example a role address;
  re:<regex>           ignore findings whose matched text matches <regex>;
  size-exclude:<glob>  leave matching paths out of the size count.
The allowlist file itself is not scanned.

Run locally (title and body are optional):
  python3 tools/pr_hygiene.py --base origin/main --head HEAD \
      --title "..." --body-file body.md
In CI the workflow passes --event "$GITHUB_EVENT_PATH" instead.
Self-test: python3 tools/pr_hygiene_test.py
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field

CAP = 1000
ALLOW_FILE = ".github/pr-hygiene-allow.txt"

# Paths that do not count towards the size cap (see AGENTS.md, "Pull request size").
SIZE_EXCLUDE = [
    "*.import", "*.uid", "*.md", "docs/*", ".github/pull_request_template.md",
    # art, sound and font assets
    "*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.svg", "*.bmp", "*.tga",
    "*.ico", "*.icns", "*.aseprite", "*.ase", "*.psd", "*.kra", "*.xcf",
    "*.wav", "*.ogg", "*.mp3", "*.flac", "*.opus",
    "*.ttf", "*.otf", "*.woff", "*.woff2",
    # lockfiles
    "*.lock", "package-lock.json", "*/package-lock.json", "pnpm-lock.yaml",
    "*/pnpm-lock.yaml",
    # generated output and vendored code
    ".godot/*", "artifacts/*", "build/*", "export/*", "addons/*",
]

EMAIL_RE = re.compile(r"(?<![\w.+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b")
# "icon@2x.png" and similar are file names, not addresses.
FILE_TLDS = {
    "png", "jpg", "jpeg", "webp", "gif", "svg", "wav", "ogg", "mp3", "gd", "tscn",
    "tres", "import", "json", "txt", "md", "py", "sh", "cfg", "uid", "res", "zip",
}
ALLOWED_EMAIL_DOMAINS = (
    "users.noreply.github.com", "noreply.github.com", "github.com",
    "example.com", "example.org", "example.net",
)
PATH_RES = [
    re.compile(r"(?<![\w.:/~-])/home/[A-Za-z0-9._-]+"),
    re.compile(r"(?<![\w.:/~-])/Users/[A-Za-z0-9._-]+"),
    re.compile(r"(?<![\w])[A-Za-z]:[\\/]+Users[\\/]+[A-Za-z0-9._ -]*"),
    re.compile(r"(?<![\w.:/~-])/" r"workspace/"),  # split so this line is not a match
]
ATTRIBUTION_RES = [
    re.compile(r"\bthe (?:owner|maintainer|user)\s+(?:wants|wanted|asked|says|said|prefers|likes|thinks|decided)\b", re.I),
    re.compile(r"\b[A-Z][a-z]+\s+(?:says|said|wants|wanted|asked for|prefers)\b"),
    re.compile(r"\b(?:per|as requested by|requested by|according to)\s+@?[A-Z][A-Za-z0-9-]+\b"),
]
SIZE_LINE_RE = re.compile(r"^\s*(?:[-*]\s*)?\**Size\**\s*:", re.I | re.M)
JUSTIFY_RE = re.compile(r"^\s*#{1,6}\s*Why this is large\b|^\s*(?:[-*]\s*)?\**Size justification\**\s*:\s*\S", re.I | re.M)


@dataclass
class Allow:
    exact: set = field(default_factory=set)
    regexes: list = field(default_factory=list)
    size_exclude: list = field(default_factory=list)

    def ok(self, text: str) -> bool:
        return text.lower() in self.exact or any(r.search(text) for r in self.regexes)

    @classmethod
    def parse(cls, text: str) -> "Allow":
        allow = cls()
        for raw in text.splitlines():
            line = raw.split("#", 1)[0].strip() if not raw.strip().startswith("re:") else raw.strip()
            if not line:
                continue
            if line.startswith("re:"):
                allow.regexes.append(re.compile(line[3:].strip()))
            elif line.startswith("size-exclude:"):
                allow.size_exclude.append(line[len("size-exclude:"):].strip())
            else:
                allow.exact.add(line.lower())
        return allow


@dataclass
class PR:
    title: str = ""
    body: str = ""
    commits: list = field(default_factory=list)  # commit messages only
    added: list = field(default_factory=list)  # (path, line_no, text)
    numstat: list = field(default_factory=list)  # (added, removed, path); None for binary
    author: str = ""
    repo: str = ""


@dataclass
class Finding:
    level: str  # "error" or "warning"
    where: str
    message: str
    path: str = ""
    line: int = 0


def counted_size(numstat, allow: Allow) -> tuple[int, list]:
    total, counted = 0, []
    globs = SIZE_EXCLUDE + allow.size_exclude
    for added, removed, path in numstat:
        if added is None or any(fnmatch.fnmatch(path, g) for g in globs):
            continue
        total += added + removed
        counted.append((added + removed, path))
    return total, sorted(counted, reverse=True)


def _emails(text: str, allow: Allow):
    for m in EMAIL_RE.finditer(text):
        addr = m.group(0)
        domain = addr.rsplit("@", 1)[1].lower()
        if domain.rsplit(".", 1)[-1] in FILE_TLDS:
            continue
        if any(domain == d or domain.endswith("." + d) for d in ALLOWED_EMAIL_DOMAINS):
            continue
        if allow.ok(addr):
            continue
        yield addr


def _paths(text: str, allow: Allow):
    for rx in PATH_RES:
        for m in rx.finditer(text):
            if not allow.ok(m.group(0)):
                yield m.group(0)


def _login_hits(text: str, login: str, repo: str):
    if not login or len(login) < 3:
        return False
    if repo:
        text = re.sub(re.escape(repo), "", text, flags=re.I)
    text = re.sub(r"https?://\S+", "", text)
    return re.search(r"(?<![\w-])@?" + re.escape(login) + r"(?![\w-])", text, re.I) is not None


def check(pr: PR, allow: Allow, cap: int = CAP) -> list:
    out: list = []
    texts = [("PR title", pr.title, "", 0), ("PR body", pr.body, "", 0)]
    texts += [(f"commit message {i + 1}", msg, "", 0) for i, msg in enumerate(pr.commits)]
    texts += [(f"{p}:{n}", t, p, n) for p, n, t in pr.added if p != ALLOW_FILE]

    for where, text, path, line in texts:
        for addr in _emails(text, allow):
            out.append(Finding("error", where, f"email address '{addr}'", path, line))
        for hit in _paths(text, allow):
            out.append(Finding("error", where, f"local path '{hit}'", path, line))
        for rx in ATTRIBUTION_RES:
            for m in rx.finditer(text):
                if not allow.ok(m.group(0)):
                    out.append(Finding("warning", where, f"possible attribution '{m.group(0)}'", path, line))
        if _login_hits(text, pr.author, pr.repo):
            out.append(Finding("warning", where, "mentions the PR author's login", path, line))

    size, counted = counted_size(pr.numstat, allow)
    if size > cap:
        top = ", ".join(f"{p} ({n})" for n, p in counted[:5])
        if JUSTIFY_RE.search(pr.body or ""):
            out.append(Finding("warning", "size", f"{size} counted code lines (cap ~{cap}); justified in the PR body. Largest: {top}"))
        else:
            out.append(Finding("error", "size", f"{size} counted code lines, over the ~{cap} cap, and the PR body has no '## Why this is large' section or 'Size justification:' line. Split the PR or justify it. Largest: {top}"))
    if not SIZE_LINE_RE.search(pr.body or ""):
        out.append(Finding("warning", "PR body", f"no 'Size:' line (counted size here: {size} code lines)"))
    return out


# ---- collecting a PR from git -------------------------------------------------

def _git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def parse_added(diff: str) -> list:
    added, path, line = [], None, 0
    for raw in diff.splitlines():
        if raw.startswith("+++ "):
            target = raw[4:]
            path = None if target == "/dev/null" else target[2:] if target.startswith("b/") else target
        elif raw.startswith("@@"):
            m = re.search(r"\+(\d+)", raw)
            line = int(m.group(1)) if m else 0
        elif raw.startswith("+") and path is not None:
            added.append((path, line, raw[1:]))
            line += 1
    return added


def parse_numstat(text: str) -> list:
    rows = []
    for raw in text.splitlines():
        parts = raw.split("\t")
        if len(parts) < 3:
            continue
        a, d, path = parts[0], parts[1], parts[-1]
        rows.append((None, None, path) if a == "-" else (int(a), int(d), path))
    return rows


def collect(base: str, head: str) -> PR:
    rng = f"{base}...{head}"
    msgs = _git("log", "--format=%B%x00", f"{base}..{head}").split("\0")
    return PR(
        commits=[m.strip() for m in msgs if m.strip()],
        added=parse_added(_git("diff", "--no-color", "--no-ext-diff", "-U0", rng)),
        numstat=parse_numstat(_git("diff", "--numstat", "--no-renames", rng)),
    )


def report(findings: list, size_note: str) -> int:
    errors = [f for f in findings if f.level == "error"]
    warnings = [f for f in findings if f.level == "warning"]
    in_ci = os.environ.get("GITHUB_ACTIONS") == "true"
    for f in findings:
        if in_ci:
            loc = f"file={f.path},line={f.line}," if f.path else ""
            print(f"::{f.level} {loc}title=pr-hygiene::{f.where}: {f.message}")
        else:
            print(f"{f.level.upper()}: {f.where}: {f.message}")
    status = "FAIL" if errors else "PASS"
    summary = [f"## PR hygiene: {status}", "", size_note, "",
               f"{len(errors)} error(s), {len(warnings)} warning(s).", ""]
    for f in errors + warnings:
        summary.append(f"- **{f.level}** {f.where}: {f.message}")
    summary += ["", "False positive? Add an entry to `.github/pr-hygiene-allow.txt` (see the header of `tools/pr_hygiene.py`)."]
    print("\n".join(summary))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as fh:
            fh.write("\n".join(summary) + "\n")
    return 1 if errors else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--event", help="GitHub pull_request event JSON (CI)")
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--title", default="")
    ap.add_argument("--body-file")
    ap.add_argument("--author", default="", help="PR author login (warning-only check)")
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    ap.add_argument("--cap", type=int, default=CAP)
    args = ap.parse_args(argv)

    title, body, author, base, head = args.title, "", args.author, args.base, args.head
    if args.body_file:
        with open(args.body_file, encoding="utf-8") as fh:
            body = fh.read()
    if args.event:
        with open(args.event, encoding="utf-8") as fh:
            pr_ev = json.load(fh)["pull_request"]
        title, body = pr_ev.get("title") or "", pr_ev.get("body") or ""
        author = (pr_ev.get("user") or {}).get("login", "")
        base, head = pr_ev["base"]["sha"], pr_ev["head"]["sha"]

    allow = Allow()
    if os.path.exists(ALLOW_FILE):
        with open(ALLOW_FILE, encoding="utf-8") as fh:
            allow = Allow.parse(fh.read())

    pr = collect(base, head)
    pr.title, pr.body, pr.author, pr.repo = title, body, author, args.repo
    size, _ = counted_size(pr.numstat, allow)
    return report(check(pr, allow, args.cap), f"Counted size: {size} code lines (cap ~{args.cap}).")


if __name__ == "__main__":
    sys.exit(main())
