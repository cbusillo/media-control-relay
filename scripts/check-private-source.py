#!/usr/bin/env python3
"""Scan public source, recognizing exact inline-code workflow metadata paths.

Metadata keys come from the repository's declared schema. Only complete code
references are removed from a candidate line; URLs and other matches on that
same line are still checked. Diagnostics contain locations, never host values.
"""

from __future__ import annotations

import base64
import json
import re
import subprocess
import sys
from pathlib import Path

PRIVATE = r"\b(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|169\.254\.[0-9]{1,3}\.[0-9]{1,3})\b|(?i:\.local\b)"
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


def scan(root: Path) -> bool:
    metadata = json.loads((root / ".github/github.json").read_text())
    if not isinstance(metadata, dict):
        raise TypeError("invalid workflow metadata")
    paths = metadata_paths(metadata)
    command = ["rg", "--json", "--hidden"]
    for excluded in (".git/**", ".build/**", "MediaControlRelay.xcodeproj/**", ".venv/**",
                     "scratch/**", "scripts/check-secrets.sh", "scripts/check-private-source.py"):
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
            print(f"{text_field(data['path'])}:{data.get('line_number') or '?'}: private network address")
            found = True
    if result.returncode == 0 and not matched:
        raise ValueError("source search evidence missing")
    return found


def main() -> int:
    try:
        return int(scan(Path(__file__).resolve().parents[1]))
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        print("Public source scan unavailable; check workflow metadata and ripgrep.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
