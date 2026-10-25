#!/usr/bin/env python3
"""Track stable GitHub releases until their version is public on the Mac App Store.

Reads Apple without credentials. Only this workflow's tracking issues are mutated;
it never submits builds or changes App Store Connect. Inspired by Context Panel's
scripts/app-store-release-status.py, reduced to MCR's single delivery channel.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen

RECORD = "mcr-app-store-release:v1"
OBSERVATION = "mcr-app-store-observation:v1"
WORKFLOW_ACTOR = "github-actions[bot]"


class StatusError(RuntimeError):
    pass


def version(value: str) -> tuple[int, ...]:
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){1,2}", value):
        raise StatusError("expected a numeric App Store version")
    parts = [int(part) for part in value.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


def marker(kind: str, value: dict) -> str:
    return f"<!-- {kind} {json.dumps(value, sort_keys=True)} -->"


def read_marker(kind: str, body: str) -> dict | None:
    matches = re.findall(r"<!-- " + re.escape(kind) + r" (.*?) -->", body, re.DOTALL)
    if not matches:
        return None
    if len(matches) != 1:
        raise StatusError("ambiguous tracking marker")
    value = json.loads(matches[0])
    if not isinstance(value, dict):
        raise StatusError("invalid tracking marker")
    return value


class GitHub:
    def __init__(self, repository: str):
        if not re.fullmatch(r"[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+", repository):
            raise StatusError("invalid repository")
        self.repository = repository

    def api(self, path: str, body: dict | None = None, method: str = "POST"):
        command = ["gh", "api", f"repos/{self.repository}/{path}"]
        if body is not None:
            command += ["--method", method, "--input", "-"]
        result = subprocess.run(
            command, input=json.dumps(body) if body is not None else None,
            text=True, capture_output=True, timeout=60, check=False,
        )
        if result.returncode:
            raise StatusError("GitHub request failed; check this workflow's permissions")
        return json.loads(result.stdout)

    def pages(self, path: str) -> list[dict]:
        items = []
        for page in range(1, 101):
            separator = "&" if "?" in path else "?"
            batch = self.api(f"{path}{separator}per_page=100&page={page}")
            if not isinstance(batch, list):
                raise StatusError("invalid GitHub inventory")
            items.extend(batch)
            if len(batch) < 100:
                return items
        raise StatusError("GitHub inventory truncated")


def public_version(payload: dict, app_id: int) -> str | None:
    """An empty, valid lookup is normal before the first App Store release."""
    if not isinstance(payload, dict):
        raise StatusError("invalid Apple lookup response")
    results = payload.get("results")
    count = payload.get("resultCount")
    if not isinstance(results, list) or type(count) is not int or count != len(results):
        raise StatusError("invalid Apple lookup response")
    if count == 0:
        return None
    if count != 1:
        raise StatusError("Apple lookup is ambiguous")
    app = results[0]
    if not isinstance(app, dict):
        raise StatusError("invalid Apple app record")
    if app.get("trackId") != app_id or app.get("kind") != "mac-software":
        raise StatusError("Apple lookup did not confirm this Mac app")
    value = app.get("version")
    version(value)
    return value


def fetch_public_version(config: dict) -> str | None:
    query = urlencode({"id": config["appId"], "entity": "macSoftware",
                       "country": config["storefront"]})
    with urlopen(f"https://itunes.apple.com/lookup?{query}", timeout=30) as response:
        return public_version(json.load(response), config["appId"])


def ensure_record(client, issues: list[dict], release: dict, target: str) -> dict:
    record = {"releaseId": release["id"], "version": target}
    matches = []
    for issue in issues:
        if "pull_request" in issue or issue.get("user", {}).get("login") != WORKFLOW_ACTOR:
            continue
        saved = read_marker(RECORD, issue.get("body") or "")
        if saved and saved.get("releaseId") == record["releaseId"]:
            if saved != record:
                raise StatusError("tracking record disagrees with its GitHub release")
            matches.append(issue)
    if len(matches) > 1:
        raise StatusError("duplicate release records; no automatic closure is safe")
    if matches:
        return matches[0]
    url = f"https://github.com/{client.repository}/releases/tag/{release['tag_name']}"
    issue = client.api("issues", {
        "title": f"App Store release pending: {target}",
        "body": (
            f"Track public Mac App Store delivery of [{release['tag_name']}]({url}).\n\n"
            "The scheduled App Store Release Status workflow owns this record. "
            "It stays open until Apple publicly lists this version. GitHub publication, "
            "TestFlight and review submission alone do not complete delivery. "
            "The configured lag allowance starts when this record is created.\n\n"
            "This records marketing-version availability, not exact binary/build identity "
            "or an installed storefront-update test. Broader qualification stays in #16.\n\n"
            + marker(RECORD, record)
        ),
    })
    issues.append(issue)
    return issue


def observe(client, issue: dict, target: str, public: str | None,
            unknown: bool, now: datetime, lag_hours: int) -> dict:
    created = datetime.fromisoformat(issue["created_at"].replace("Z", "+00:00"))
    if created.tzinfo is None:
        raise StatusError("tracking timestamp has no time zone")
    overdue = now - created >= timedelta(hours=lag_hours)
    if unknown:
        status = "unknown"
    elif public is not None and version(public) == version(target):
        status = "live"
    elif public is not None and version(public) > version(target):
        status = "superseded"
    else:
        status = "overdue" if overdue else "pending"
    value = {"version": target, "publicVersion": public, "status": status}
    comments = client.pages(f"issues/{issue['number']}/comments")
    observations = [read_marker(OBSERVATION, comment.get("body") or "")
                    for comment in comments
                    if comment.get("user", {}).get("login") == WORKFLOW_ACTOR]
    previous = [item for item in observations if item is not None]
    if not previous or previous[-1] != value:
        client.api(f"issues/{issue['number']}/comments", {
            "body": f"App Store delivery: **{status}**. Target: {target}; "
            f"public US Mac version: {public or 'not established'}.\n\n"
            "Live means this marketing version is publicly available; it does not identify "
            "the exact build or prove installed update behavior. A newer public version "
            "supersedes this record without claiming this older version went live. "
            "Pending/overdue does not distinguish waiting for review from rejection. "
            "For overdue or unknown delivery, inspect Apple's review response or the failed "
            "lookup before changing anything. No App Store Connect mutation was made.\n\n"
            + marker(OBSERVATION, value),
        })
    if status in {"live", "superseded"} and issue["state"] == "open":
        client.api(f"issues/{issue['number']}", {
            "state": "closed", "state_reason": "completed" if status == "live" else "not_planned",
        }, method="PATCH")
    return {"issue": issue["number"], **value}


def monitor(client, config: dict, now: datetime, lookup=fetch_public_version) -> list[dict]:
    # Read both inventories completely before any write. PRs and foreign-authored
    # issue markers are never adopted; closed not-planned records stay retired.
    releases = client.pages("releases")
    issues = client.pages("issues?state=all")
    targets = []
    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        match = re.fullmatch(r"v?(\d+(?:\.\d+){1,2})", release.get("tag_name", ""))
        if match:
            targets.append((release, match[1]))
    if not targets:
        return []
    try:
        public = lookup(config)
        if public is not None:
            version(public)
        unknown = False
    except (OSError, ValueError, TypeError, KeyError, StatusError):
        public, unknown = None, True
    outcomes = []
    for release, target in targets:
        issue = ensure_record(client, issues, release, target)
        if issue.get("state_reason") == "not_planned":
            continue
        outcomes.append(observe(client, issue, target, public, unknown, now, config["lagHours"]))
    return outcomes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--config", type=Path,
                        default=Path(__file__).resolve().parents[1] / "Config/AppStoreRelease.json")
    parser.add_argument("--lookup-only", action="store_true", help="read Apple without GitHub writes")
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text())
        if (type(config["appId"]) is not int or config["appId"] <= 0
                or not re.fullmatch(r"[a-z]{2}", config["storefront"])
                or type(config["lagHours"]) is not int or config["lagHours"] <= 0):
            raise StatusError("invalid App Store release configuration")
        if args.lookup_only:
            print(json.dumps({"publicVersion": fetch_public_version(config)}))
            return 0
        outcomes = monitor(GitHub(args.repo), config, datetime.now(timezone.utc))
        print(json.dumps(outcomes, indent=2))
        return int(any(item["status"] in {"overdue", "unknown"} for item in outcomes))
    except (OSError, ValueError, TypeError, KeyError, StatusError, subprocess.SubprocessError) as error:
        print(f"Release status unavailable: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
