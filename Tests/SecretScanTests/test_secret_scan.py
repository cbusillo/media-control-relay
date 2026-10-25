import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIELD_PARTS = ("commands", "unit", "local")
HOST_PARTS = ("example-target", "local")
FIELD = ".".join(FIELD_PARTS)
HOST = ".".join(HOST_PARTS)
METADATA = {"commands": {"unit": {"local": "run-unit"}}}


class SecretScanTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        shutil.copyfile(ROOT / "scripts/check-secrets.sh", self.root / "scripts/check-secrets.sh")
        shutil.copyfile(ROOT / "scripts/check-private-source.py", self.root / "scripts/check-private-source.py")
        (self.root / ".github").mkdir()
        (self.root / ".github/github.json").write_text(json.dumps(METADATA))

    def scan(self, content, env=None):
        (self.root / "README.md").write_text(content)
        return subprocess.run(["sh", str(self.root / "scripts/check-secrets.sh")],
                              text=True, capture_output=True, check=False, env=env)

    def test_declared_metadata_reference_is_public_code(self):
        result = self.scan(f"Use `{FIELD}` from workflow metadata.\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_private_hosts_still_fail_in_prose_code_and_urls(self):
        host = HOST
        for text in (host, host.upper(), f"`{host}`", f"https://{host}/", f"`https://{FIELD}/`"):
            with self.subTest(text=text):
                result = self.scan(text)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(text.strip("`"), result.stdout + result.stderr)

    def test_metadata_reference_does_not_hide_other_matches_on_the_line(self):
        addresses = [".".join(parts) for parts in (("10", "7", "8", "9"),
                     ("192", "168", "7", "8"), ("172", "16", "7", "8"),
                     ("172", "31", "7", "8"), ("169", "254", "7", "8"),
                     ("example-target", "local"))]
        for address in addresses:
            with self.subTest(address=address):
                result = self.scan(f"Use `{FIELD}`; connect to https://{address}/.")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(address, result.stdout + result.stderr)

    def test_only_complete_declared_code_references_are_recognized(self):
        for text in (FIELD, f"`other.{FIELD}`", f"`{FIELD}.other`", f"`{FIELD.upper()}`"):
            with self.subTest(text=text):
                self.assertNotEqual(self.scan(text).returncode, 0)
        self.assertEqual(self.scan(f"Use ``{FIELD}``.").returncode, 0)

    def test_untracked_secret_file_still_fails(self):
        (self.root / ".env").write_text("synthetic fixture")
        self.assertNotEqual(self.scan("ordinary public prose").returncode, 0)

    def test_non_utf8_source_does_not_hide_addresses(self):
        address = HOST
        (self.root / "sample.txt").write_bytes(b"\xff" + address.encode())
        self.assertNotEqual(self.scan("ordinary public prose").returncode, 0)

    def test_missing_or_unreadable_scan_evidence_cannot_pass(self):
        tools = self.root / "tools"
        tools.mkdir()
        rg = tools / "rg"
        env = {**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"]}
        for body in ("exit 2", "exit 0", "printf '%s\\n' invalid-json"):
            with self.subTest(body=body):
                rg.write_text("#!/bin/sh\n" + body + "\n")
                rg.chmod(0o755)
                self.assertNotEqual(self.scan("public prose", env=env).returncode, 0)
        (self.root / ".github/github.json").unlink()
        self.assertNotEqual(self.scan("public prose").returncode, 0)


if __name__ == "__main__":
    unittest.main()
