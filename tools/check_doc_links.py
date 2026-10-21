#!/usr/bin/env python3
"""Check docs/**/*.md for broken links, missing file references and stale 'coming' facts.

Checks, per markdown file under docs/ (fenced code blocks are skipped):

1. Relative markdown links ``[text](path)`` must resolve to an existing file or
   directory, relative to the markdown file. Anchors and queries are stripped.
   Links starting with ``/`` resolve from the repo root.
2. Backtick file paths such as ``supabase/phase99.sql``, ``web/optionsx.js`` or
   ``tests/...`` must exist, either relative to the repo root or relative to the
   markdown file. Glob patterns (``*``) pass when they match at least one path.
3. Stale facts: a line that says a branch, phase or file is "coming" /
   "coming soon" / "not yet" is flagged when the branch, phase file or report it
   names now exists in the repo or in git refs.

Usage:
    python3 tools/check_doc_links.py            # report, exit 1 if any finding
    python3 tools/check_doc_links.py --root DIR  # check another checkout

Output is one finding per line: ``file:line  KIND  target  -- detail``.
"""

from __future__ import annotations

import argparse
import fnmatch
import glob
import os
import re
import subprocess
import sys
from dataclasses import dataclass

LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
CODE_RE = re.compile(r"`([^`\n]+)`")
PATH_CHARS_RE = re.compile(r"^[A-Za-z0-9_./*\-]+$")
FILE_EXT_RE = re.compile(
    r"\.(sql|js|py|md|html|css|json|sh|yml|yaml|toml|csv|txt|webp|svg|png|jpg|"
    r"ps1|xml|ts|env|lock|ini|cfg)$"
)
COMING_RE = re.compile(r"\bcoming\b", re.IGNORECASE)
BRANCH_RE = re.compile(r"\b((?:feat|fix|docs|chore|integration)/[A-Za-z0-9_.\-]+)")
PHASE_RE = re.compile(r"\bphase[ _-]?(\d{1,4})\b", re.IGNORECASE)
STEP_REPORT_RE = re.compile(r"\b((?:docs/briefs_p2p3/)?(?:step_|p\d)[A-Za-z0-9_]*_REPORT\.md)\b")


@dataclass
class Finding:
    file: str
    line: int
    kind: str
    target: str
    detail: str

    def __str__(self) -> str:
        return f"{self.file}:{self.line}  {self.kind}  {self.target}  -- {self.detail}"


def iter_md_files(root: str):
    docs = os.path.join(root, "docs")
    for dirpath, _dirs, files in os.walk(docs):
        for name in files:
            if name.endswith(".md"):
                full = os.path.join(dirpath, name)
                yield os.path.relpath(full, root)


def fenced_free_lines(text: str):
    """Yield (lineno, line) for lines outside fenced code blocks."""
    in_fence = False
    for i, line in enumerate(text.splitlines(), start=1):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            yield i, line


# Starts with a letter, digit or './' (not '-', '/', '_test.sql', '.ext').
PATH_START_RE = re.compile(r"^(?:[A-Za-z0-9]|\./)")
# Git branch names and remote refs are not file paths.
NON_PATH_PREFIX_RE = re.compile(r"^(?:feat|fix|docs|chore|integration|origin|warn|warning)/[A-Za-z0-9_.\-]+$")
# Template placeholders such as phaseNN_test.sql, phase1NN.sql, phase4N_test.sql, YYYY/MM/DD/.
PLACEHOLDER_RE = re.compile(r"NN|YYYY|\dN|MM/DD")


def _first_segment_exists(root: str, rel_md_dir: str, span: str) -> bool:
    first = span.split("/", 1)[0]
    if not first:
        return False
    for base in (root, os.path.join(root, rel_md_dir), os.path.join(root, "docs")):
        if os.path.exists(os.path.join(base, first)):
            return True
    return False


SKIP_DIRS = {".git", "node_modules", "__pycache__"}


def basename_index(root: str) -> dict[str, list[str]]:
    """Map every file basename in the repo to its repo-relative paths."""
    index: dict[str, list[str]] = {}
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            index.setdefault(name, []).append(
                os.path.relpath(os.path.join(dirpath, name), root))
    return index


def shorthand_match(target: str, index: dict[str, list[str]]) -> str | None:
    """Repo path that ends with ``/target``, e.g. ``supabase/functions/x/index.ts``
    written as ``x/index.ts``. Returns the first such path, or None."""
    base = target.rstrip("/").rsplit("/", 1)[-1]
    for rel in index.get(base, []):
        if rel == target or rel.endswith("/" + target.rstrip("/")):
            return rel
    return None


def exists_any(root: str, rel_md_dir: str, target: str,
               index: dict[str, list[str]] | None = None) -> bool:
    """True if target exists from the repo root, the markdown file's dir or docs/.

    A bare file name with no directory (e.g. ``pos.js``) is accepted when a file
    of that name exists anywhere in the repo, because the docs often name a
    module by its file name only. A relative path that matches the end of a
    repo path (e.g. ``data/kb.json`` for ``web/data/kb.json``) is also accepted;
    check_file reports those as SHORTHAND_PATH, not as failures.
    """
    candidates = [os.path.join(root, target), os.path.join(root, rel_md_dir, target),
                  os.path.join(root, "docs", target)]
    for cand in candidates:
        if "*" in target:
            if glob.glob(cand):
                return True
        elif os.path.exists(cand):
            return True
    if index is not None:
        if "*" in target:
            return any(fnmatch.fnmatch(n, target) for n in index)
        if "/" not in target:
            return target in index
        return shorthand_match(target, index) is not None
    return False


def git_refs(root: str) -> set[str]:
    """Names of remote-tracking branches (origin/ prefix removed).

    Only remote refs count as 'exists': a branch that is local to one worktree
    has not been published, so a doc saying it is still coming is not stale.
    """
    try:
        out = subprocess.run(
            ["git", "-C", root, "for-each-ref", "--format=%(refname:short)",
             "refs/remotes"],
            capture_output=True, text=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return set()
    refs = set()
    for ref in out.split():
        if ref.startswith("origin/") and ref != "origin/HEAD":
            refs.add(ref[len("origin/"):])
    return refs


NEAR_CHARS = 60
UNRELATED_COMING_RE = re.compile(r"\bcoming\s+(days|back|from|to|in|out|up)\b", re.IGNORECASE)


def _stale_candidates(line: str):
    """Yield (match, name, detail) for branches/phases/reports that now exist."""
    coming_spans = [m.span() for m in COMING_RE.finditer(line)
                    if not UNRELATED_COMING_RE.match(line, m.start())]
    if not coming_spans:
        return

    def near(pos: int) -> bool:
        return any(a - NEAR_CHARS <= pos <= b + NEAR_CHARS for a, b in coming_spans)

    for m in BRANCH_RE.finditer(line):
        name = m.group(1).rstrip(".")
        if near(m.start()) and name in REFS_CACHE:
            yield m, name, "described as coming but branch exists"
    for m in PHASE_RE.finditer(line):
        num = m.group(1)
        if near(m.start()) and os.path.exists(
                os.path.join(ROOT_CACHE, "supabase", f"phase{num}.sql")):
            yield m, f"phase{num}", f"described as coming but supabase/phase{num}.sql exists"
    for m in STEP_REPORT_RE.finditer(line):
        name = m.group(1)
        if near(m.start()) and exists_any(ROOT_CACHE, "", name):
            yield m, name, "described as coming but report exists"


REFS_CACHE: set[str] = set()
ROOT_CACHE = ""


def check_file(root: str, rel: str, refs: set[str],
               index: dict[str, list[str]]) -> list[Finding]:
    findings: list[Finding] = []
    rel_dir = os.path.dirname(rel)
    with open(os.path.join(root, rel), encoding="utf-8") as fh:
        text = fh.read()

    for lineno, line in fenced_free_lines(text):
        # 1. markdown links
        for m in LINK_RE.finditer(line):
            target = m.group(1).strip("<>")
            if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#"):
                continue
            path = target.split("#", 1)[0].split("?", 1)[0]
            if not path:
                continue
            if path.startswith("/"):
                ok = os.path.exists(os.path.join(root, path.lstrip("/")))
            else:
                ok = os.path.exists(os.path.join(root, rel_dir, path))
            if not ok:
                findings.append(Finding(rel, lineno, "BROKEN_LINK", target,
                                        "relative link target not found"))

        # 2. backtick file paths
        for m in CODE_RE.finditer(line):
            span = m.group(1).strip()
            if "://" in span or any(c in span for c in "<>{}()=,;| ") or ".." in span:
                continue
            if not PATH_CHARS_RE.match(span) or not PATH_START_RE.match(span):
                continue
            if PLACEHOLDER_RE.search(span) or NON_PATH_PREFIX_RE.match(span):
                continue
            has_ext = bool(FILE_EXT_RE.search(span))
            clean = span.rstrip("/")
            if clean in ("", ".", ".."):
                continue
            if "/" not in clean and not has_ext:
                continue
            if "/" in clean and not has_ext and not _first_segment_exists(root, rel_dir, clean):
                # 'lists/list_options', 'latest/', 'a/b' alternatives: not a path
                continue
            if exists_any(root, rel_dir, clean):
                continue
            hint = shorthand_match(clean, index) if "/" in clean else None
            if hint:
                findings.append(Finding(rel, lineno, "SHORTHAND_PATH", span,
                                        f"resolves to {hint} (info only)"))
                continue
            if exists_any(root, rel_dir, clean, index):
                continue
            findings.append(Finding(rel, lineno, "MISSING_PATH", span,
                                    "backtick path not found in repo"))

        # 3. stale 'coming' facts
        # A reference counts only when 'coming' sits within NEAR_CHARS of it,
        # so unrelated uses of the word ("coming days") do not match.
        for m, name, detail in _stale_candidates(line):
            if name is None:
                continue
            findings.append(Finding(rel, lineno, "STALE_COMING", name, detail))
    return findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--root", default=None,
                        help="repo root (default: parent of this script's directory)")
    args = parser.parse_args(argv)
    root = os.path.abspath(args.root or os.path.join(os.path.dirname(__file__), ".."))

    refs = git_refs(root)
    REFS_CACHE.update(refs)
    global ROOT_CACHE
    ROOT_CACHE = root
    index = basename_index(root)
    findings: list[Finding] = []
    files = sorted(iter_md_files(root))
    for rel in files:
        findings.extend(check_file(root, rel, refs, index))

    for f in findings:
        print(f)
    counts: dict[str, int] = {}
    for f in findings:
        counts[f.kind] = counts.get(f.kind, 0) + 1
    print(f"\nfiles scanned: {len(files)}")
    for kind in sorted(counts):
        print(f"{kind}: {counts[kind]}")
    print(f"total findings: {len(findings)}")
    failures = [f for f in findings if f.kind != "SHORTHAND_PATH"]
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
