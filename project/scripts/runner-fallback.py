# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
"""Retry a main build on Intel when the Arm runner queue stops making progress."""
import json
import os
import subprocess
import time


QUEUE_WAIT = 300
WATCH_LIMIT = 5400


def mac_jobs(jobs):
    return [job for job in jobs if job["name"] == "checks" or job["name"].startswith(("package (", "ios ("))]


def decision(jobs, waited):
    if any(job["name"] == "checks" and job["status"] == "completed" and job.get("conclusion") != "success" for job in jobs):
        return "done"
    mac = mac_jobs(jobs)
    if not mac:
        return "wait"
    if any(job["status"] == "completed" and job.get("conclusion") != "success" for job in mac):
        return "done"
    variants = ("rootless", "jailed", "rootful", "roothide")
    if all(any(job["name"].startswith("package (" + variant + ")") and job["status"] == "completed"
               for job in mac) for variant in variants):
        return "done"
    if any(job["status"] not in ("queued", "completed") for job in mac):
        return "wait"
    return "fallback" if any(job["status"] == "queued" for job in mac) and waited >= QUEUE_WAIT else "wait"


def api(path, payload=None):
    command = ["gh", "api", path]
    if payload is not None:
        command += ["--method", "POST", "--input", "-"]
    output = subprocess.check_output(command, text=True, timeout=30,
                                     input=json.dumps(payload) if payload is not None else None)
    return json.loads(output) if output.strip() else None


def watch():
    repository = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    run_id = os.environ["GITHUB_RUN_ID"]
    prefix = "repos/" + repository
    started = time.monotonic()
    idle_since = None
    while time.monotonic() - started < WATCH_LIMIT:
        jobs = api(prefix + "/actions/runs/" + run_id + "/jobs?per_page=100")["jobs"]
        now = time.monotonic()
        mac = mac_jobs(jobs)
        if any(job["status"] not in ("queued", "completed") for job in mac):
            idle_since = None
        elif idle_since is None:
            idle_since = now
        action = decision(jobs, now - idle_since if idle_since is not None else 0)
        if action == "done":
            print("macOS jobs finished; no runner retry.", flush=True)
            return
        if action == "fallback":
            head = api(prefix + "/git/ref/heads/main")["object"]["sha"]
            if head != sha:
                print("A newer commit supersedes this run.", flush=True)
                return
            api(prefix + "/actions/workflows/build.yml/dispatches", {
                "ref": "main",
                "inputs": {"runner": "macos-15-intel", "runner_fallback": True, "source_commit": sha},
            })
            print("Dispatched one Intel retry for " + sha + ".", flush=True)
            return
        time.sleep(30)
    print("Runner watcher expired; the existing build continues.", flush=True)


if __name__ == "__main__":
    watch()
