# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("runner_fallback", Path(__file__).resolve().parents[1] / "scripts/runner-fallback.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def job(status, conclusion=None, name="package (rootless)"):
    return {"name": name, "status": status, "conclusion": conclusion}


class RunnerFallbackTests(unittest.TestCase):
    def test_waits_before_jobs_exist(self):
        self.assertEqual(runner.decision([], 900), "wait")

    def test_queue_gets_grace_period(self):
        self.assertEqual(runner.decision([job("queued")], 299), "wait")

    def test_idle_queue_retries_after_grace_period(self):
        self.assertEqual(runner.decision([job("queued")], 300), "fallback")

    def test_running_job_is_never_interrupted(self):
        self.assertEqual(runner.decision([job("queued"), job("in_progress")], 900), "wait")

    def test_successful_jobs_prevent_destructive_whole_run_retry(self):
        self.assertEqual(runner.decision([job("completed", "success"), job("queued")], 900), "done")

    def test_test_failure_is_not_hidden_by_runner_retry(self):
        self.assertEqual(runner.decision([job("completed", "failure"), job("queued")], 900), "done")

    def test_finished_build_is_not_retried(self):
        self.assertEqual(runner.decision([job("completed", "success", name="package (" + variant + ") / build") for variant in ("rootless", "jailed", "rootful", "roothide")], 900), "done")

    def test_linux_watcher_does_not_block_its_own_retry(self):
        self.assertEqual(runner.decision([job("in_progress", name="runner_fallback"), job("queued")], 900), "fallback")

    def test_linux_failure_stops_runner_retry(self):
        self.assertEqual(runner.decision([job("completed", "failure", name="checks"), job("queued")], 900), "done")

    def test_dispatch_is_pinned_and_limited_to_one_retry(self):
        with patch.dict(runner.os.environ, {"GITHUB_REPOSITORY": "owner/repo", "GITHUB_SHA": "abc", "GITHUB_RUN_ID": "42"}):
            with patch.object(runner, "QUEUE_WAIT", 0), patch.object(runner.time, "monotonic", return_value=1):
                with patch.object(runner, "api", side_effect=[{"jobs": [job("queued")]}, {"object": {"sha": "abc"}}, None]) as api:
                    runner.watch()
        self.assertEqual(api.call_count, 3)
        payload = api.call_args.args[1]
        self.assertEqual(payload["ref"], "main")
        self.assertEqual(payload["inputs"], {"runner": "macos-15-intel", "runner_fallback": True, "source_commit": "abc"})

    def test_newer_commit_cancels_fallback_dispatch(self):
        with patch.dict(runner.os.environ, {"GITHUB_REPOSITORY": "owner/repo", "GITHUB_SHA": "abc", "GITHUB_RUN_ID": "42"}):
            with patch.object(runner, "QUEUE_WAIT", 0), patch.object(runner.time, "monotonic", return_value=1):
                with patch.object(runner, "api", side_effect=[{"jobs": [job("queued")]}, {"object": {"sha": "new"}}]) as api:
                    runner.watch()
        self.assertEqual(api.call_count, 2)

    def test_queued_shared_checks_can_use_runner_fallback(self):
        self.assertEqual(runner.decision([job("queued", name="checks")], 300), "fallback")

    def test_shared_checks_completion_preserves_artifacts(self):
        self.assertEqual(runner.decision([job("completed", "success", name="checks")], 900), "done")

    def test_first_package_completion_preserves_build(self):
        self.assertEqual(runner.decision([job("completed", "success")], 900), "done")


if __name__ == "__main__":
    unittest.main()
