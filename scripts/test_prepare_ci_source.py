#!/usr/bin/env python3
"""Focused regressions for the native CI source gate; no compiler build."""
from pathlib import Path
import hashlib
import subprocess
import tempfile
import unittest

from prepare_ci_source import prepare


class SourceGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "source"
        self.root.mkdir()
        self.runner_temp = self.base / "runner"
        self.runner_temp.mkdir()
        for args in (("init", "-q"), ("config", "user.name", "Gate test"),
                     ("config", "user.email", "gate@example.invalid")):
            subprocess.run(["git", *args], cwd=self.root, check=True)
        (self.root / ".roc-version").write_text("nightly-2026-11-07-ad3a5d2\n")
        (self.root / "source.roc").write_text("source bytes\n")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"],
                       cwd=self.root, check=True)
        self.sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root, text=True).strip()
        import platform
        system = {"Linux": "linux_x86_64", "Darwin": "macos_apple_silicon"}[platform.system()]
        self.compiler = self.root / f"roc_nightly-{system}-2026-11-07-ad3a5d2" / "roc"
        self.compiler.parent.mkdir()
        self.compiler.write_text("#!/bin/sh\necho 'Roc compiler version nightly-2026-11-07-ad3a5d2'\n")
        self.compiler.chmod(0o755)

    def run_gate(self, compiler=None, sha=None):
        receipt = {}
        prepare(self.root, compiler or self.compiler, self.runner_temp, sha or self.sha, receipt)
        return receipt

    def test_relocates_only_compiler_and_records_clean_source(self):
        original = self.compiler.read_bytes()
        receipt = self.run_gate()
        self.assertFalse(self.compiler.exists())
        self.assertEqual(Path(receipt["compiler"]["path"]).read_bytes(), original)
        self.assertEqual(receipt["compiler"]["sha256"], hashlib.sha256(original).hexdigest())
        self.assertEqual(receipt["source_revision"], self.sha)
        self.assertEqual(receipt["status_after"], [])
        self.assertEqual(receipt["tracked_diff_after"], "")
        self.assertEqual(receipt["tracked_sha256"]["source.roc"],
                         hashlib.sha256(b"source bytes\n").hexdigest())

    def test_rejects_unstaged_and_staged_tracked_changes(self):
        (self.root / "source.roc").write_text("changed\n")
        with self.assertRaisesRegex(ValueError, "tracked source changed"):
            self.run_gate()
        subprocess.run(["git", "add", "source.roc"], cwd=self.root, check=True)
        with self.assertRaisesRegex(ValueError, "tracked source changed"):
            self.run_gate()
        self.assertTrue(self.compiler.exists())

    def test_rejects_untracked_changes(self):
        (self.root / "unexpected.roc").write_text("unexpected\n")
        with self.assertRaisesRegex(ValueError, "unexpected checkout state"):
            self.run_gate()
        self.assertTrue(self.compiler.exists())

    def test_refuses_unrelated_install_directory(self):
        unrelated = self.root / "unrelated" / "roc"
        self.compiler.parent.rename(unrelated.parent)
        with self.assertRaisesRegex(ValueError, "exact pinned"):
            self.run_gate(compiler=unrelated)
        self.assertTrue(unrelated.exists())

    def test_refuses_wrong_revision(self):
        with self.assertRaisesRegex(ValueError, "requested source revision"):
            self.run_gate(sha="0" * 40)
        self.assertTrue(self.compiler.exists())

    def test_refuses_wrong_compiler_version(self):
        self.compiler.write_text("#!/bin/sh\necho 'Roc compiler version other'\n")
        with self.assertRaisesRegex(ValueError, "differs from the pinned nightly"):
            self.run_gate()
        self.assertTrue(self.compiler.exists())


if __name__ == "__main__":
    unittest.main()
