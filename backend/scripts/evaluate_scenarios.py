"""End-to-end scenario evaluation through the public API.

Usage: python scripts/evaluate_scenarios.py [--url http://127.0.0.1:8000]
       [--scenarios ../docs/evaluation/scenarios.json] [--images DIR]

Each scenario sends a real image to /api/v1/scan and checks the outcome
against ground truth written by a person. This measures the *application*
pipeline (detector + rules + guidance), not detector accuracy alone, and a
passing scenario does not show that guidance is safe in the real world.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parent.parent


def check(expect: dict, body: dict, target: str | None) -> list[str]:
    problems = []
    dets = body["detection"]["detections"]
    labels = [d["label"] for d in dets]
    ctx = body["context"]
    for lbl in expect.get("labels_present", []):
        if lbl not in labels:
            problems.append(f"missing label {lbl}")
    for lbl, n in expect.get("min_count", {}).items():
        if labels.count(lbl) < n:
            problems.append(f"expected >= {n} {lbl}, got {labels.count(lbl)}")
    for text in expect.get("guidance_contains", []):
        if text not in ctx["guidance"]["message"]:
            problems.append(f"guidance lacks '{text}'")
    if expect.get("no_seats") and ctx["seats"]:
        problems.append(f"unexpected seats: {[s['label'] for s in ctx['seats']]}")
    if "max_exit_confidence" in expect:
        exits = [c["confidence"] for c in (body.get("signs") or {}).get("candidates", []) if c["kind"] == "exit_sign"]
        if exits and max(exits) > expect["max_exit_confidence"]:
            problems.append(f"false exit sign with confidence {max(exits):.2f}")
    if "target_found" in expect:
        found = target in labels
        if found != expect["target_found"]:
            problems.append(f"target '{target}' found={found}, expected {expect['target_found']}")
    return problems


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--url", default="http://127.0.0.1:8000")
    p.add_argument("--scenarios", type=Path, default=ROOT.parent / "docs" / "evaluation" / "scenarios.json")
    p.add_argument("--images", type=Path, default=os.environ.get("SMARTSIGHT_EVAL_IMAGES"))
    p.add_argument("--json", type=Path)
    args = p.parse_args()
    images = args.images
    if images is None:
        from ultralytics.utils import ASSETS
        images = Path(ASSETS)

    spec = json.loads(args.scenarios.read_text(encoding="utf-8"))
    rows = []
    with httpx.Client(base_url=args.url, timeout=60) as c:
        for s in spec["scenarios"]:
            data = {"task": s["task"]}
            if s.get("target_label"):
                data["target_label"] = s["target_label"]
            img = (Path(images) / s["image"]).read_bytes()
            r = c.post("/api/v1/scan", files={"image": (s["image"], img, "image/jpeg")}, data=data)
            r.raise_for_status()
            body = r.json()
            problems = check(s["expect"], body, s.get("target_label"))
            rows.append({"id": s["id"], "passed": not problems, "problems": problems,
                         "guidance": body["context"]["guidance"]["message"]})
    passed = sum(r["passed"] for r in rows)
    report = {"passed": passed, "total": len(rows), "scenarios": rows,
              "note": "Application-level checks on a tiny image set; not evidence of real-world safety."}
    print(json.dumps(report, indent=2))
    if args.json:
        args.json.write_text(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
