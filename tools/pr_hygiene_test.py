#!/usr/bin/env python3
"""Self-test for tools/pr_hygiene.py. Run: python3 tools/pr_hygiene_test.py

Fixture strings that the check must flag are assembled from pieces at run time,
so this file itself contains no email address or local path.
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pr_hygiene as h  # noqa: E402

AT = "@"
EMAIL = "jane.doe" + AT + "mail" + ".test"
NOREPLY = "12345+someone" + AT + "users.noreply.github.com"
HOME_PATH = "/" + "home" + "/someone/project/main.gd"
MAC_PATH = "/" + "Users" + "/someone/project"
WIN_PATH = "C:" + "\\" + "Users" + "\\someone\\project"
SCRATCH_PATH = "/" + "workspace" + "/flagoria/tools"
ATTRIBUTION = "the owner " + "wants a bigger map"
CLEAN_BODY = "## Why\nFix a thing.\n\nSize: ~40 code lines\n"
BIG = [(900, 300, "Scripts/big.gd")]

FIXTURES = [
    # name, PR fields, expected error count, expected warning substrings (None: no warnings)
    ("clean", dict(body=CLEAN_BODY, added=[("Scripts/a.gd", 1, "var x = 1")], numstat=[(10, 2, "Scripts/a.gd")]), 0, None),
    ("email in body", dict(body=CLEAN_BODY + "Contact " + EMAIL), 1, []),
    ("email in added line", dict(body=CLEAN_BODY, added=[("README.md", 3, "mail " + EMAIL)]), 1, []),
    ("email in commit message", dict(body=CLEAN_BODY, commits=["fix: thing\n\nCo-authored-by: X <" + EMAIL + ">"]), 1, []),
    ("noreply allowed", dict(body=CLEAN_BODY, commits=["Co-authored-by: X <" + NOREPLY + ">"]), 0, None),
    ("file name is not an email", dict(body=CLEAN_BODY, added=[("a.tscn", 1, 'path="res://icon' + AT + '2x.png"')]), 0, None),
    ("home path in added line", dict(body=CLEAN_BODY, added=[("tools/x.sh", 2, "cd " + HOME_PATH)]), 1, []),
    ("mac path in title", dict(title="Fix " + MAC_PATH, body=CLEAN_BODY), 1, []),
    ("windows path in body", dict(body=CLEAN_BODY + WIN_PATH), 1, []),
    ("scratch path in body", dict(body=CLEAN_BODY + "see " + SCRATCH_PATH), 1, []),
    ("url is not a path", dict(body=CLEAN_BODY + "https://example.test/home/page"), 0, None),
    ("attribution is a warning", dict(body=CLEAN_BODY + ATTRIBUTION), 0, ["attribution"]),
    ("missing Size line is a warning", dict(body="## Why\nFix."), 0, ["Size:"]),
    ("author login is a warning, repo slug is not", dict(author="octo-dev", repo="octo-dev/game",
        body=CLEAN_BODY + "See octo-dev/game#3 and https://github.com/octo-dev/game/pull/3. Thanks octo-dev."), 0, ["login"]),
    ("repo slug alone is fine", dict(author="octo-dev", repo="octo-dev/game", body=CLEAN_BODY + "Part of octo-dev/game#3"), 0, None),
    ("over cap", dict(body=CLEAN_BODY, numstat=BIG), 1, []),
    ("over cap + justification line", dict(body=CLEAN_BODY + "Size justification: one generated-looking table.\n", numstat=BIG), 0, ["justified"]),
    ("over cap + why-large section", dict(body=CLEAN_BODY + "## Why this is large\nIt cannot be split.\n", numstat=BIG), 0, ["justified"]),
    ("excluded files do not count", dict(body=CLEAN_BODY, numstat=[
        (5000, 0, "art/x.png.import"), (3000, 0, "docs/big.md"), (2000, 0, "Scripts/a.gd.uid"),
        (None, None, "art/hero.png"), (1500, 0, ".github/pull_request_template.md"), (900, 0, "Scripts/a.gd")]), 0, None),
]


def run_fixtures(allow: h.Allow) -> int:
    failed = 0
    for name, fields, want_errors, want_warn in FIXTURES:
        findings = h.check(h.PR(**fields), allow)
        errors = [f for f in findings if f.level == "error"]
        warns = " | ".join(f.message for f in findings if f.level == "warning")
        ok = len(errors) == want_errors and (
            not warns if want_warn is None else all(w in warns for w in want_warn))
        print(f"{'ok  ' if ok else 'FAIL'} {name}: {len(errors)} error(s); warnings: {warns or '-'}")
        failed += not ok
    return failed


def run_allowlist() -> int:
    allow = h.Allow.parse("# comment\n" + EMAIL + "\nre:^/" + "home/someone\nsize-exclude:Scripts/big.gd\n")
    pr = h.PR(body=CLEAN_BODY + EMAIL + " " + HOME_PATH, numstat=BIG)
    errors = [f for f in h.check(pr, allow) if f.level == "error"]
    ok = not errors
    print(f"{'ok  ' if ok else 'FAIL'} allowlist file (exact, re:, size-exclude:): {len(errors)} error(s)")
    return not ok


def run_git_end_to_end() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        def git(*a):
            subprocess.run(["git", "-C", tmp, *a], check=True, capture_output=True,
                           env={**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t" + AT + "t.test",
                                "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t" + AT + "t.test"})
        git("init", "-q", "-b", "main")
        with open(os.path.join(tmp, "a.gd"), "w") as fh:
            fh.write("var a = 1\n")
        git("add", "."); git("commit", "-q", "-m", "base")
        git("checkout", "-q", "-b", "feature")
        with open(os.path.join(tmp, "a.gd"), "a") as fh:
            fh.write("var b = 2\n# " + EMAIL + "\n")
        with open(os.path.join(tmp, "x.png.import"), "w") as fh:
            fh.write("x\n" * 50)
        git("add", "."); git("commit", "-q", "-m", "add b")
        cwd = os.getcwd()
        os.chdir(tmp)
        try:
            pr = h.collect("main", "feature")
        finally:
            os.chdir(cwd)
    size, _ = h.counted_size(pr.numstat, h.Allow())
    pr.body = CLEAN_BODY
    errors = [f for f in h.check(pr, h.Allow()) if f.level == "error"]
    # The author email is in git metadata only, so it must not be reported.
    ok = (size == 2 and pr.commits == ["add b"] and len(errors) == 1
          and errors[0].path == "a.gd" and errors[0].line == 3)
    print(f"{'ok  ' if ok else 'FAIL'} git end-to-end: size={size}, commits={pr.commits}, "
          f"errors={[(e.path, e.line) for e in errors]}")
    return not ok


def main() -> int:
    failed = run_fixtures(h.Allow()) + run_allowlist() + run_git_end_to_end()
    print(f"\n{len(FIXTURES) + 2 - failed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
