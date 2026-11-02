# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("ios_runner", Path(__file__).resolve().parents[1] / "scripts/test-ios.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class SimulatorRecoveryTests(unittest.TestCase):
    def test_shutdown_failure_stops_recovery(self):
        with patch.object(runner, "simctl_quiet", side_effect=[True, False]) as command:
            with patch.object(runner, "warm_up") as warm:
                self.assertFalse(runner.reset("device"))
        self.assertEqual(command.call_count, 2)
        warm.assert_not_called()

    def test_boot_failure_stops_recovery(self):
        with patch.object(runner, "simctl_quiet", side_effect=[True, True, False]) as command:
            self.assertFalse(runner.reset("device"))
        self.assertEqual(command.call_count, 3)

    def test_bootstatus_failure_is_not_ready(self):
        with patch.object(runner, "simctl_quiet", side_effect=[True, True, True, False]):
            with patch.object(runner, "warm_up") as warm:
                self.assertFalse(runner.reset("device"))
        warm.assert_not_called()

    def test_warm_up_failure_is_not_ready(self):
        with patch.object(runner, "simctl_quiet", return_value=True):
            with patch.object(runner, "warm_up", return_value=False):
                self.assertFalse(runner.reset("device"))

    def test_recovery_requires_successful_app_launch(self):
        with patch.object(runner, "simctl_quiet", return_value=True):
            with patch.object(runner, "warm_up", return_value=True) as warm:
                self.assertTrue(runner.reset("device"))
        warm.assert_called_once_with("device", timeout=30)

    def test_failed_recovery_cannot_continue_fixture(self):
        with patch.object(runner, "reset", return_value=False):
            with self.assertRaisesRegex(RuntimeError, "unhealthy device"):
                runner.require_reset("device")


if __name__ == "__main__":
    unittest.main()
