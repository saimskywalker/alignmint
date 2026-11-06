#!/usr/bin/env python3
"""Check one --format json result read from stdin.

Used by CI and, when python3 is installed, by test/run.sh. Neither the
checker nor the test suite needs Python; this only adds a strict parse on
machines that have it. Exits non-zero with a message if anything is off.
"""
import json
import sys

obj = json.loads(sys.stdin.read())  # rejects trailing data: one object only
assert isinstance(obj, dict), "not a JSON object"

envelope = ["schemaVersion", "tool", "exitCode", "summary", "findings"]
assert list(obj)[:5] == envelope, f"envelope fields out of order: {list(obj)[:5]}"
assert obj["schemaVersion"] == 1, "schemaVersion"
assert obj["tool"]["name"] == "alignmint", "tool.name"

severities = ("error", "warning", "info")
for f in obj["findings"]:
    assert f["severity"] in severities, f"severity {f['severity']}"
    assert f["id"] and f["message"], "finding needs id and message"
counts = {s: sum(f["severity"] == s for f in obj["findings"]) for s in severities}
assert obj["summary"] == counts, f"summary {obj['summary']} != findings {counts}"

verdicts = {"aligned": 0, "unaligned": 1, "unverified": 2}
assert verdicts[obj["verdict"]] == obj["exitCode"], "verdict does not match exitCode"
assert (obj["exitCode"] == 0) == (counts["error"] == 0), "error findings do not match exitCode"

for lib in obj["libraries"]:
    assert lib["status"] in ("ok", "fail", "skip", "none"), f"status {lib['status']}"
