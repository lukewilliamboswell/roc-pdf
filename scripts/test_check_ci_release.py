#!/usr/bin/env python3
"""Ordinary-CI identity cannot authorize changed bytes or a non-forward release."""
import copy
import errno
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import check_ci_release as admission
from check_ci_release import check_ci_release


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.candidate = Path(self.directory.name) / "hash.tar.zst"
        self.payload = b"whole package including embedded resources"
        self.candidate.write_bytes(self.payload)
        self.metadata = {
            "tag_name": "0.3.0", "immutable": True, "draft": False, "prerelease": False,
            "assets": [{"name": self.candidate.name, "id": 7, "state": "uploaded",
                        "size": len(self.payload), "digest": "sha256:" + hashlib.sha256(self.payload).hexdigest(),
                        "browser_download_url": "https://github.com/lukewilliamboswell/roc-pdf/releases/download/0.3.0/hash.tar.zst"}],
        }
        self.fetches = []

    def fetch(self, asset_id, size):
        self.fetches.append((asset_id, size))
        return self.payload

    def check(self, requested="0.3.0", explicit="", **kwargs):
        check_ci_release(requested, explicit, self.metadata, self.candidate,
                         fetch=kwargs.pop("fetch", self.fetch), **kwargs)

    def test_exact_complete_bytes_are_admitted_only_for_ordinary_ci(self):
        self.check()
        self.assertEqual(self.fetches, [(7, len(self.payload))])
        with self.assertRaisesRegex(ValueError, "move forward"):
            self.check(explicit="0.3.0")
        self.assertEqual(len(self.fetches), 1)

    def test_changed_candidate_same_name_and_length_is_rejected(self):
        self.candidate.write_bytes(b"X" + self.payload[1:])
        with self.assertRaisesRegex(ValueError, "candidate bytes differ"):
            self.check()
        self.assertEqual(self.fetches, [])

    def test_wrong_candidate_length_name_and_symlink_are_rejected(self):
        self.candidate.write_bytes(self.payload + b"x")
        with self.assertRaises(ValueError): self.check()
        self.candidate.write_bytes(self.payload)
        old = self.candidate
        self.candidate = old.with_name("different.tar.zst")
        self.candidate.write_bytes(self.payload)
        with self.assertRaises(ValueError): self.check()
        self.candidate.unlink()
        self.candidate.symlink_to(old)
        with self.assertRaises(ValueError): self.check()

    def test_changed_truncated_or_failed_download_cannot_pass(self):
        for bad in (b"X" + self.payload[1:], self.payload[:-1], self.payload + b"x"):
            with self.subTest(download=bad), self.assertRaises(ValueError):
                self.check(fetch=lambda *_: bad)
        def failed(*_): raise subprocess.CalledProcessError(1, ["gh", "api"])
        with self.assertRaises(subprocess.CalledProcessError): self.check(fetch=failed)

    def test_invalid_release_and_asset_metadata_fail_closed(self):
        mutations = [
            ("immutable", False), ("draft", True), ("prerelease", True), ("tag_name", "0.3.0-rc1"),
            ("assets", []), ("assets", self.metadata["assets"] * 2),
        ]
        original = copy.deepcopy(self.metadata)
        for key, value in mutations:
            with self.subTest(key=key, value=value):
                self.metadata = copy.deepcopy(original)
                self.metadata[key] = value
                with self.assertRaises((ValueError, KeyError)): self.check()
        for key, value in [("digest", "sha256:" + "0" * 64), ("digest", "bad"),
                           ("size", 0), ("size", True), ("id", True), ("id", -1),
                           ("state", "new"), ("browser_download_url", "https://example.com/hash.tar.zst"),
                           ("name", "../hash.tar.zst")]:
            with self.subTest(key=key, value=value):
                self.metadata = copy.deepcopy(original)
                self.metadata["assets"][0][key] = value
                with self.assertRaises((ValueError, KeyError)): self.check()
        self.metadata = copy.deepcopy(original)
        del self.metadata["assets"][0]["digest"]
        with self.assertRaises(KeyError): self.check()

    def test_older_malformed_and_explicit_mismatched_versions_fail(self):
        for requested in ("0.2.9", "0.03.0", "0.3.0-rc1"):
            with self.subTest(requested=requested), self.assertRaises(ValueError): self.check(requested)
        with self.assertRaisesRegex(ValueError, "explicit release input"):
            self.check(explicit="0.3.1")

    def test_future_ordinary_and_explicit_releases_keep_exact_strict_path(self):
        for explicit in ("", "0.3.1"):
            calls = []
            def strict(*args): calls.append(args)
            self.check("0.3.1", explicit, strict=strict)
            self.assertEqual(calls, [("0.3.1", "0.3.0", self.metadata["assets"][0]["browser_download_url"])])
        self.assertEqual(self.fetches, [])

    def test_strict_api_failures_propagate_and_breaking_proof_is_retained(self):
        def failed(*_): raise subprocess.CalledProcessError(1, ["roc", "bump"])
        with self.assertRaises(subprocess.CalledProcessError):
            self.check("0.3.1", "0.3.1", strict=failed)
        self.check("0.4.0", "0.4.0")
        self.assertEqual(self.fetches, [])


    def test_byte_ceiling_rejects_metadata_and_candidate_before_read(self):
        self.metadata["assets"][0]["size"] = admission.MAX_BUNDLE_BYTES + 1
        with patch.object(Path, "open", side_effect=AssertionError("must not read")):
            with self.assertRaisesRegex(ValueError, "length or digest"):
                self.check()
        self.metadata["assets"][0]["size"] = len(self.payload)
        with self.candidate.open("wb") as candidate:
            candidate.truncate(admission.MAX_BUNDLE_BYTES + 1)
        with patch.object(Path, "open", side_effect=AssertionError("must not read")):
            with self.assertRaisesRegex(ValueError, "candidate length"):
                self.check()
        self.assertEqual(self.fetches, [])


class TransportTests(unittest.TestCase):
    def test_real_output_limits_hang_and_descriptor_closure(self):
        for program, expected in [
            ("import sys; sys.stdout.write('x'*10000)", "stdout-limit"),
            ("import sys; sys.stderr.write('x'*10000)", "stderr-limit"),
            ("import time; time.sleep(10)", "timeout"),
        ]:
            with self.subTest(expected=expected):
                processes = []
                real_popen = subprocess.Popen
                def create(*args, **kwargs):
                    process = real_popen(*args, **kwargs)
                    processes.append(process)
                    return process
                with patch.object(admission.subprocess, "Popen", side_effect=create):
                    _, body, stderr, reason = admission.bounded_api(
                        [sys.executable, "-c", program], 64, seconds=0.2 if expected == "timeout" else 5)
                self.assertEqual(reason, expected)
                self.assertLessEqual(len(body), 65)
                self.assertLessEqual(len(stderr), admission.MAX_STDERR_BYTES + 1)
                self.assertTrue(processes[0].stdout.closed and processes[0].stderr.closed)
                self.assertIsNotNone(processes[0].returncode)

    def test_real_descendant_held_pipes_timeout_and_oversize_have_one_group_cleanup(self):
        for mode in ("timeout", "stdout-limit"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temporary:
                started, marker = Path(temporary) / "started", Path(temporary) / "survived"
                child = ("import os,json,time,pathlib; pathlib.Path(" + repr(str(started))
                         + ").write_text(json.dumps({'pid':os.getpid(),'pgid':os.getpgrp(),'sid':os.getsid(0)}));"
                         + " time.sleep(1.2); pathlib.Path(" + repr(str(marker)) + ").write_text('alive')")
                parent = "import subprocess,sys,time,pathlib; subprocess.Popen([sys.executable,'-c'," + repr(child) + "]);"
                parent += "\nwhile not pathlib.Path(" + repr(str(started)) + ").exists(): time.sleep(0.005)\n"
                if mode == "stdout-limit":
                    parent += "sys.stdout.write('x'*10000); sys.stdout.flush(); time.sleep(10)"
                # In timeout mode the parent exits normally while the actual
                # child holds both pipes, reproducing the rejected Timer bug.
                processes, signals, identities = [], [], []
                real_popen, real_killpg = subprocess.Popen, os.killpg
                def create(*args, **kwargs):
                    self.assertTrue(kwargs["start_new_session"])
                    process = real_popen(*args, **kwargs)
                    processes.append(process)
                    identities.append((process.pid, os.getpgid(process.pid), os.getsid(process.pid)))
                    return process
                def kill_once(group, sent):
                    signals.append((group, sent))
                    if len(signals) > 1:
                        raise PermissionError(errno.EPERM, "second signal to cleaned group")
                    real_killpg(group, sent)
                before = time.monotonic()
                with patch.object(admission.subprocess, "Popen", side_effect=create), patch.object(admission.os, "killpg", side_effect=kill_once):
                    _, _, _, reason = admission.bounded_api([sys.executable, "-c", parent], 64, seconds=0.5)
                self.assertEqual(reason, mode)
                self.assertLess(time.monotonic() - before, 6.5)
                self.assertTrue(started.exists())
                process, = processes
                self.assertEqual(identities, [(process.pid, process.pid, process.pid)])
                self.assertNotEqual(os.getpgrp(), process.pid)
                self.assertEqual(signals, [(process.pid, signal.SIGKILL)])
                self.assertTrue(process.stdout.closed and process.stderr.closed)
                identity = json.loads(started.read_text())
                self.assertEqual((identity["pgid"], identity["sid"]), (process.pid, process.pid))
                time.sleep(1.3)
                self.assertFalse(marker.exists())
                state = subprocess.run(["ps", "-p", str(identity["pid"]), "-o", "pid=,pgid=,stat="],
                                       capture_output=True, text=True, timeout=2)
                if state.returncode == 1:
                    self.assertEqual(state.stdout.strip(), "")
                else:
                    self.assertEqual(state.returncode, 0, state.stderr)
                    pid, group, status = state.stdout.split()
                    self.assertEqual((int(pid), int(group)), (identity["pid"], process.pid))
                    self.assertTrue(status.startswith("Z"), state.stdout)

    def test_first_cleanup_signal_and_reap_errors_remain_failures_with_closed_descriptors(self):
        for failure in ("first-signal", "reap"):
            with self.subTest(failure=failure):
                processes, selectors_seen = [], []
                real_popen, real_selector = subprocess.Popen, admission.selectors.DefaultSelector
                def create(*args, **kwargs):
                    process = real_popen(*args, **kwargs)
                    processes.append(process)
                    if failure == "reap":
                        real_wait = process.wait
                        def wait(*args, **kwargs):
                            result = real_wait(*args, **kwargs)
                            if kwargs.get("timeout") == 5:
                                raise subprocess.TimeoutExpired(process.args, 5)
                            return result
                        process.wait = wait
                    return process
                def select():
                    selector = real_selector()
                    selectors_seen.append(selector)
                    return selector
                with patch.object(admission.subprocess, "Popen", side_effect=create), patch.object(admission.selectors, "DefaultSelector", side_effect=select):
                    if failure == "first-signal":
                        with patch.object(admission.os, "killpg", side_effect=PermissionError(errno.EPERM, "first signal refused")):
                            with self.assertRaises(PermissionError):
                                admission.bounded_api([sys.executable, "-c", "print('complete')"], 64, seconds=5)
                    else:
                        with self.assertRaises(subprocess.TimeoutExpired):
                            admission.bounded_api([sys.executable, "-c", "import time; time.sleep(10)"], 64, seconds=0.1)
                process, = processes
                self.assertIsNotNone(process.returncode)
                self.assertTrue(process.stdout.closed and process.stderr.closed)
                self.assertIsNone(selectors_seen[0].get_map())

    def test_normal_exit_still_cleans_descendants_that_closed_their_pipes(self):
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary) / "survived"
            child = "import time,pathlib; time.sleep(0.5); pathlib.Path(" + repr(str(marker)) + ").write_text('alive')"
            parent = "import subprocess,sys; subprocess.Popen([sys.executable,'-c'," + repr(child) + "],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)"
            code, _, _, reason = admission.bounded_api([sys.executable, "-c", parent], 64, seconds=2)
            self.assertEqual((code, reason), (0, "exited"))
            time.sleep(0.7)
            self.assertFalse(marker.exists())

    def test_metadata_and_assets_are_bounded_official_gets_without_echoing_stderr(self):
        with patch.object(admission, "bounded_api", return_value=(0, b'{"tag_name":"0.3.0"}', b"", "exited")) as bounded:
            self.assertEqual(admission.fetch_latest(), {"tag_name": "0.3.0"})
            self.assertEqual(bounded.call_args.args, (["gh", "api", "--hostname", "github.com", "--method", "GET", "repos/lukewilliamboswell/roc-pdf/releases/latest"], admission.MAX_METADATA_BYTES))
        with patch.object(admission, "bounded_api", return_value=(0, b"body", b"", "exited")) as bounded:
            self.assertEqual(admission.fetch_asset(7, 4), b"body")
            self.assertEqual(bounded.call_args.args, (["gh", "api", "--hostname", "github.com", "--method", "GET", "repos/lukewilliamboswell/roc-pdf/releases/assets/7", "--header", "Accept: application/octet-stream"], 4))
        with patch.object(admission, "bounded_api", return_value=(1, b"", b"synthetic-secret", "stderr-limit")):
            with self.assertRaisesRegex(ValueError, "stderr-limit") as error:
                admission.fetch_latest()
            self.assertNotIn("synthetic-secret", str(error.exception))
        with patch.object(admission, "bounded_api") as bounded:
            for size in (0, admission.MAX_BUNDLE_BYTES + 1, True):
                with self.assertRaises(ValueError): admission.fetch_asset(7, size)
            bounded.assert_not_called()

    def test_authentication_is_environment_only_and_debug_is_cleared(self):
        with patch.dict(os.environ, {"GH_TOKEN": "synthetic-secret", "GH_DEBUG": "api"}):
            command = [sys.executable, "-c", "import os; print('auth' if os.environ.get('GH_TOKEN') else 'missing'); print(os.environ.get('GH_DEBUG','no-debug'))"]
            code, body, stderr, reason = admission.bounded_api(command, 100)
            self.assertEqual((code, body, stderr, reason), (0, b"auth\nno-debug\n", b"", "exited"))
            self.assertNotIn("synthetic-secret", str(command))


if __name__ == "__main__":
    unittest.main()
