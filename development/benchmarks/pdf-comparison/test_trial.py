"""Failure-path checks for trustworthy trial measurements; no PDF libraries needed."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

import trial


class TrialChecks(unittest.TestCase):
    def test_failed_command_retains_diagnostics(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            sample = trial.measure(
                [sys.executable, "-c", "import sys; print('output'); print('diagnostic',file=sys.stderr); sys.exit(7)"],
                directory, dict(os.environ), directory / "failed", 10,
            )
            self.assertEqual(sample["exit_code"], 7)
            self.assertFalse(sample["timed_out"])
            self.assertIn("diagnostic", Path(sample["stderr"]).read_text())
            self.assertIn("output", Path(sample["stdout"]).read_text())
            self.assertGreater(sample["wall_ns"], 0)
            self.assertGreater(sample["wait4_maxrss_bytes"], 0)

    def test_timeout_is_not_a_successful_sample(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            sample = trial.measure([sys.executable, "-c", "import time; time.sleep(30)"],
                                   directory, dict(os.environ), directory / "timeout", 0.1)
            self.assertTrue(sample["timed_out"])
            self.assertLess(sample["exit_code"], 0)

    def test_metrics_reject_missing_duplicate_and_unreconciled_records(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "stdout"
            record = {"schema": 1, "write_ns": 3, "generate_ns": 7, "application_ns": 10, "pdf_bytes": 42}
            line = trial.MARKER + json.dumps(record) + "\n"
            output.write_text(line)
            self.assertEqual(trial.metrics(output), record)
            for bad in ("", line + line, line.replace('"application_ns": 10', '"application_ns": 9')):
                output.write_text(bad)
                with self.assertRaises(ValueError):
                    trial.metrics(output)

    def test_immediate_source_edit_invalidates_python_bytecode(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            workload = json.loads((trial.HERE / "workload.json").read_text())
            command = [sys.executable, "-c", "import workload; print(workload.REVISION)"]
            trial.generate(directory, workload, False)
            self.assertEqual(trial.capture(command, cwd=directory, env=dict(os.environ)), workload["revision"])
            trial.generate(directory, workload, True)
            self.assertEqual(trial.capture(command, cwd=directory, env=dict(os.environ)), workload["edited_revision"])


if __name__ == "__main__":
    unittest.main()
