#!/usr/bin/env python3
"""Scan public source, recognizing exact inline-code workflow metadata paths.

Metadata keys come from the repository's declared schema. Only complete code
references are removed from a candidate line; URLs and other matches on that
same line are still checked. Diagnostics contain locations, never host values.
"""

from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import sys
from fnmatch import fnmatchcase
from pathlib import Path

MDNS_SUFFIX = "local"
PRIVATE = rf"\b(10\.[0-9]{{1,3}}\.[0-9]{{1,3}}\.[0-9]{{1,3}}|192\.168\.[0-9]{{1,3}}\.[0-9]{{1,3}}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{{1,3}}\.[0-9]{{1,3}}|169\.254\.[0-9]{{1,3}}\.[0-9]{{1,3}})\b|(?i:\.{MDNS_SUFFIX}\b)"
CODE = re.compile(r"(?<!`)(`+)([A-Za-z_][A-Za-z_0-9.]*)\1(?!`)")


def metadata_paths(value: dict, prefix: tuple[str, ...] = ()) -> set[str]:
    paths = set()
    for key, child in value.items():
        if not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", key):
            continue
        path = (*prefix, key)
        paths.add(".".join(path))
        if isinstance(child, dict):
            paths.update(metadata_paths(child, path))
    return paths


def text_field(value: dict) -> str:
    if isinstance(value.get("text"), str):
        return value["text"]
    return base64.b64decode(value["bytes"], validate=True).decode("utf-8", errors="replace")


def safe_location(path: str) -> str:
    return "/".join("[private]" if re.search(PRIVATE, part) else part
                    for part in Path(path).parts)


def forbidden_files(root: Path) -> list[Path]:
    patterns = (".env*", "*.env", "*.env.*", "*.p8", "*.p12", "*.pem", "*.key", "*.cer",
                "*.mobileprovision", "*.provisionprofile", "samtvcli.yaml")
    excluded = {".git", ".build", "MediaControlRelay.xcodeproj", "scratch"}
    found = []

    def unavailable(error):
        raise error

    for directory, dirs, files in os.walk(root, onerror=unavailable):
        here = Path(directory)
        dirs[:] = [name for name in dirs if name != ".venv"
                   and not (here == root and name in excluded)]
        for name in files:
            path = here / name
            if not path.is_symlink() and path.is_file() and any(fnmatchcase(name, pattern)
                                                             for pattern in patterns):
                found.append(path.relative_to(root))
    return found


def scan(root: Path) -> bool:
    metadata = json.loads((root / ".github/github.json").read_text())
    if not isinstance(metadata, dict):
        raise TypeError("invalid workflow metadata")
    paths = metadata_paths(metadata)
    command = ["rg", "--json", "--hidden"]
    for excluded in (".git/**", ".build/**", "MediaControlRelay.xcodeproj/**", ".venv/**",
                     "scratch/**"):
        command += ["--glob", f"!{excluded}"]
    command += [PRIVATE, "."]
    result = subprocess.run(command, cwd=root, text=True, capture_output=True, check=False)
    if result.returncode not in (0, 1):
        raise ValueError("source search failed")
    found = False
    matched = False
    for row in result.stdout.splitlines():
        record = json.loads(row)
        if record["type"] != "match":
            continue
        matched = True
        data = record["data"]
        line = text_field(data["lines"])
        line = CODE.sub(lambda match: " " * len(match[0]) if match[2] in paths else match[0], line)
        if re.search(PRIVATE, line):
            print(f"{safe_location(text_field(data['path']))}:{data.get('line_number') or '?'}: private network address", file=sys.stderr)
            found = True
    if result.returncode == 0 and not matched:
        raise ValueError("source search evidence missing")
    return found


def main() -> int:
    try:
        root = Path(__file__).resolve().parents[1]
        forbidden = forbidden_files(root)
        if forbidden:
            print("Forbidden secret-bearing files found:", file=sys.stderr)
            for path in forbidden:
                print(safe_location(str(path)), file=sys.stderr)
            return 1
        if scan(root):
            print("Private network address found in public source.", file=sys.stderr)
            return 1
        print("Public secret checks passed.")
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        print("Public source scan unavailable; check workflow metadata and ripgrep.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
