#!/usr/bin/env python3
"""Write results/latest.json and append results/history.csv for one run.

Reads:
  results/failed-step.txt  - failing step name, or empty when the run passed
  results/step-log.txt     - last ~30 lines of the failing step (may be absent)
Env:
  RESULTS_DIR              - defaults to results
  NEEDPEDIA_COMMIT         - full SHA of the Needpedia commit tested
  GITHUB_REPOSITORY        - e.g. eberechi10/needpedia-build-check
  GITHUB_RUN_ID            - id of this Actions run
"""
import csv
import datetime
import json
import os
import pathlib

RESULTS_DIR = os.environ.get("RESULTS_DIR", "results")
out = pathlib.Path(RESULTS_DIR)
out.mkdir(parents=True, exist_ok=True)

now = datetime.datetime.now(datetime.timezone.utc)
checked_at = now.strftime("%Y-%m-%dT%H:%M:%SZ")

failed_path = out / "failed-step.txt"
failed_step = failed_path.read_text().strip() if failed_path.exists() else "unknown"

error_lines = []
log_path = out / "step-log.txt"
if log_path.exists():
    error_lines = [line.rstrip("\n") for line in log_path.read_text(errors="replace").splitlines()]

passed = (failed_step == "")

needpedia_commit = os.environ.get("NEEDPEDIA_COMMIT", "").strip()
repo = os.environ.get("GITHUB_REPOSITORY", "")
run_id = os.environ.get("GITHUB_RUN_ID", "")
run_url = f"https://github.com/{repo}/actions/runs/{run_id}" if repo and run_id else ""

latest_path = out / "latest.json"
previous_last_passed = None
if latest_path.exists():
    try:
        previous = json.loads(latest_path.read_text())
        previous_last_passed = previous.get("last_passed_at")
    except Exception:
        previous_last_passed = None

last_passed_at = checked_at if passed else previous_last_passed

latest = {
    "checked_at": checked_at,
    "passed": passed,
    "failed_step": "" if passed else failed_step,
    "error_lines": error_lines,
    "needpedia_commit": needpedia_commit,
    "run_url": run_url,
    "last_passed_at": last_passed_at,
}
latest_path.write_text(json.dumps(latest, indent=2) + "\n")

history_path = out / "history.csv"
is_new = not history_path.exists()
with history_path.open("a", newline="") as f:
    writer = csv.writer(f)
    if is_new:
        writer.writerow(["checked_at", "passed", "failed_step", "needpedia_commit", "run_url", "last_passed_at"])
    writer.writerow([
        latest["checked_at"],
        "true" if latest["passed"] else "false",
        latest["failed_step"],
        latest["needpedia_commit"],
        latest["run_url"],
        latest["last_passed_at"] or "",
    ])
