import copy
import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "release_status", Path(__file__).resolve().parents[2] / "scripts/app-store-release-status.py"
)
status = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(status)
CONFIG = {"appId": 17, "storefront": "us"}


class FakeGitHub:
    repository = "example/relay"

    def __init__(self):
        self.releases = [{"id": 8, "tag_name": "v2.3.0", "draft": False, "prerelease": False}]
        self.issues = []
        self.comments = {}
        self.writes = []
        self.fail_close = False

    def pages(self, path):
        if path == "releases":
            return copy.deepcopy(self.releases)
        if path.startswith("issues?"):
            return copy.deepcopy(self.issues)
        return copy.deepcopy(self.comments.get(int(path.split("/")[1]), []))

    def api(self, path, body, method="POST"):
        self.writes.append((path, copy.deepcopy(body)))
        if path == "issues":
            item = {"number": len(self.issues) + 1, "state": "open", "state_reason": None, **body,
                    "user": {"login": status.WORKFLOW_ACTOR}}
            self.issues.append(item)
            return copy.deepcopy(item)
        number = int(path.split("/")[1])
        if path.endswith("/comments"):
            self.comments.setdefault(number, []).append(
                {**body, "user": {"login": status.WORKFLOW_ACTOR}}
            )
        else:
            if self.fail_close:
                raise status.StatusError("simulated uncertain close")
            self.issues[number - 1].update(body)
        return {}


class ReleaseStatusTests(unittest.TestCase):
    def run_check(self, client, public=None):
        return status.monitor(client, CONFIG, lookup=lambda _: public)

    def test_first_release_absent_then_live_creates_one_record_and_closes_it(self):
        client = FakeGitHub()
        first = self.run_check(client)
        self.assertEqual(first[0]["status"], "not_public")
        title = client.issues[0]["title"]
        client.issues[0]["title"] = "App Store release pending: 2.3.0"
        self.run_check(client)
        self.assertEqual(client.issues[0]["title"], title)
        writes = len(client.writes)
        self.run_check(client)
        self.assertEqual(len(client.issues), 1)
        self.assertEqual(len(client.writes), writes)
        live = self.run_check(client, "2.3.0")
        self.assertEqual(live[0]["status"], "live")
        self.assertEqual(client.issues[0]["state_reason"], "completed")
        writes = len(client.writes)
        self.run_check(client, "2.3.0")
        self.assertEqual(len(client.writes), writes)

    def test_absent_or_old_store_version_reports_availability_without_inferring_review(self):
        for public in (None, "2.2.9"):
            with self.subTest(public=public):
                client = FakeGitHub()
                self.run_check(client, public)
                writes = len(client.writes)
                result = self.run_check(client, public)
                self.assertEqual(result[0]["status"], "not_public")
                self.assertEqual(client.issues[0]["state"], "open")
                self.assertEqual(len(client.writes), writes)

    def test_unknown_evidence_is_not_a_missing_listing_or_success(self):
        client = FakeGitHub()

        def broken(_):
            raise OSError("lookup failed")

        result = status.monitor(client, CONFIG, lookup=broken)
        self.assertEqual(result[0]["status"], "unknown")
        self.assertEqual(client.issues[0]["state"], "open")
        self.run_check(client, "2.3.0")
        self.assertEqual(client.issues[0]["state_reason"], "completed")

    def test_newer_public_version_supersedes_without_claiming_old_release_was_live(self):
        client = FakeGitHub()
        self.run_check(client, "2.10.0")
        self.assertEqual(client.issues[0]["state_reason"], "not_planned")
        writes = len(client.writes)
        self.run_check(client, "2.10.0")
        self.assertEqual(len(client.writes), writes)

    def test_manual_retirement_is_preserved(self):
        client = FakeGitHub()
        self.run_check(client)
        client.issues[0].update(state="closed", state_reason="not_planned")
        writes = len(client.writes)
        self.run_check(client, "2.3.0")
        self.assertEqual(len(client.writes), writes)

    def test_foreign_issue_and_pr_markers_cannot_be_adopted_or_closed(self):
        for foreign in ({"user": {"login": "person"}}, {"pull_request": {}}):
            with self.subTest(foreign=foreign):
                client = FakeGitHub()
                self.run_check(client)
                client.issues[0].update(foreign)
                result = self.run_check(client, "2.3.0")
                self.assertEqual(client.issues[0]["state"], "open")
                self.assertEqual(result[0]["issue"], 2)
                self.assertEqual(client.issues[1]["state"], "closed")

    def test_forged_observation_does_not_suppress_real_update(self):
        client = FakeGitHub()
        self.run_check(client)
        client.comments[1].append({"user": {"login": "person"}, "body": status.marker(
            status.OBSERVATION, {"version": "2.3.0", "publicVersion": "2.3.0", "status": "live"}
        )})
        self.run_check(client, "2.3.0")
        self.assertEqual(len(client.comments[1]), 3)
        self.assertEqual(client.issues[0]["state_reason"], "completed")

    def test_close_failure_recovers_without_duplicating_observation_or_issue(self):
        client = FakeGitHub()
        client.fail_close = True
        with self.assertRaises(status.StatusError):
            self.run_check(client, "2.3.0")
        client.fail_close = False
        self.run_check(client, "2.3.0")
        self.assertEqual(len(client.issues), 1)
        self.assertEqual(len(client.comments[1]), 1)
        self.assertEqual(client.issues[0]["state_reason"], "completed")

    def test_duplicate_record_refuses_automatic_closure(self):
        client = FakeGitHub()
        self.run_check(client)
        client.issues.append(copy.deepcopy(client.issues[0]))
        writes = len(client.writes)
        with self.assertRaises(status.StatusError):
            self.run_check(client, "2.3.0")
        self.assertEqual(len(client.writes), writes)

    def test_only_newest_version_is_tracked_and_obsolete_records_retire(self):
        client = FakeGitHub()
        self.run_check(client)
        client.releases.append({"id": 9, "tag_name": "v2.10"})
        result = self.run_check(client)
        self.assertEqual(result[0]["version"], "2.10")
        self.assertEqual(client.issues[0]["state_reason"], "not_planned")
        self.assertEqual(client.issues[1]["state"], "open")
        fresh = FakeGitHub()
        fresh.releases = client.releases
        self.run_check(fresh)
        self.assertEqual(len(fresh.issues), 1)

    def test_withdrawn_or_retagged_release_does_not_orphan_its_record(self):
        for replacement in ([], [{"id": 8, "tag_name": "nightly"}],
                            [{"id": 8, "tag_name": "v2.3.0", "prerelease": True}],
                            [{"id": 8, "tag_name": "v2.4"}]):
            with self.subTest(replacement=replacement):
                client = FakeGitHub()
                self.run_check(client)
                client.releases = replacement
                self.run_check(client)
                self.assertEqual(client.issues[0]["state_reason"], "not_planned")
                writes = len(client.writes)
                self.run_check(client)
                self.assertEqual(len(client.writes), writes)

    def test_equivalent_retag_reuses_record_and_completed_records_stay_quiet(self):
        client = FakeGitHub()
        self.run_check(client)
        client.releases[0]["tag_name"] = "v2.3"
        self.run_check(client, "2.3.0")
        writes = len(client.writes)
        for public in (None, "2.2", "2.10"):
            self.run_check(client, public)
        self.assertEqual(len(client.writes), writes)
        self.assertEqual(len(client.issues), 1)

    def test_only_stable_numeric_publications_are_tracked(self):
        client = FakeGitHub()
        client.releases = [
            {"id": 1, "tag_name": "v2.0", "draft": True},
            {"id": 2, "tag_name": "v2.0", "prerelease": True},
            {"id": 3, "tag_name": "nightly"},
        ]
        self.assertEqual(self.run_check(client), [])
        self.assertEqual(client.writes, [])

    def test_lookup_accepts_absent_and_exact_mac_identity_only(self):
        self.assertIsNone(status.public_version({"results": [], "resultCount": 0}, CONFIG["appId"]))
        app = {"trackId": CONFIG["appId"], "kind": "mac-software", "version": "2.3.0"}
        self.assertEqual(status.public_version({"results": [app], "resultCount": 1}, CONFIG["appId"]),
                         app["version"])
        for fields in ({"trackId": 999}, {"kind": "software"}, {"version": "new"}):
            with self.subTest(fields=fields), self.assertRaises(status.StatusError):
                status.public_version({"results": [{**app, **fields}], "resultCount": 1},
                                      CONFIG["appId"])
        with self.assertRaises(status.StatusError):
            status.public_version({"results": [], "resultCount": 1}, CONFIG["appId"])
        with self.assertRaises(status.StatusError):
            status.public_version({"results": [None], "resultCount": 1}, CONFIG["appId"])
        with self.assertRaises(status.StatusError):
            status.public_version([], CONFIG["appId"])


if __name__ == "__main__":
    unittest.main()
