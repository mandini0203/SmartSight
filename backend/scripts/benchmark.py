"""Measure end-to-end API latency against a running backend.

Usage:
    python scripts/benchmark.py --url http://127.0.0.1:8000 --runs 20 [--image path.jpg ...]

Reports min / median / p90 / max wall-clock latency per endpoint, measured
from the client (includes upload, decoding, inference and JSON encoding).
These are *system* metrics for this machine; they say nothing about model
accuracy or about whether guidance is safe or useful.
"""

from __future__ import annotations

import argparse
import json
import platform
import statistics
import time
from pathlib import Path

import httpx


def percentile(values: list[float], p: float) -> float:
    s = sorted(values)
    k = min(len(s) - 1, max(0, round(p / 100 * (len(s) - 1))))
    return s[k]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8000")
    parser.add_argument("--runs", type=int, default=20)
    parser.add_argument("--image", action="append", type=Path)
    parser.add_argument("--json", type=Path, help="Write results to this JSON file")
    args = parser.parse_args()

    images = args.image
    if not images:
        from ultralytics.utils import ASSETS

        images = [Path(ASSETS) / "bus.jpg", Path(ASSETS) / "zidane.jpg"]
    blobs = [(p.name, p.read_bytes()) for p in images]

    endpoints = {
        "detection": ("/api/v1/detection", {}),
        "scan describe": ("/api/v1/scan", {"task": "describe_surroundings"}),
        "scan find_exit": ("/api/v1/scan", {"task": "find_exit"}),
        "signs": ("/api/v1/signs/detect", {}),
        "colour (centre)": ("/api/v1/colour/identify", {}),
    }
    results: dict[str, dict] = {}
    with httpx.Client(base_url=args.url, timeout=60) as c:
        c.get("/health").raise_for_status()
        status = c.get("/api/v1/status").json()
        for name, (path, data) in endpoints.items():
            # One warm-up request per endpoint is excluded from the statistics.
            c.post(path, files={"image": blobs[0]}, data=data)
            times, server = [], []
            for i in range(args.runs):
                fname, blob = blobs[i % len(blobs)]
                t = time.perf_counter()
                r = c.post(path, files={"image": (fname, blob, "image/jpeg")}, data=data)
                times.append((time.perf_counter() - t) * 1000)
                r.raise_for_status()
                body = r.json()
                ms = body.get("processing", {}).get("total_ms") or body.get("processing_ms") \
                    or body.get("detection", {}).get("processing", {}).get("total_ms")
                if ms:
                    server.append(ms)
            results[name] = {
                "runs": args.runs,
                "min_ms": round(min(times), 1),
                "median_ms": round(statistics.median(times), 1),
                "p90_ms": round(percentile(times, 90), 1),
                "max_ms": round(max(times), 1),
                "server_median_ms": round(statistics.median(server), 1) if server else None,
            }
        t = time.perf_counter()
        for _ in range(args.runs):
            c.post("/api/v1/intent/resolve", json={"text": "where is my phone"}).raise_for_status()
        results["intent"] = {"runs": args.runs, "mean_ms": round((time.perf_counter() - t) * 1000 / args.runs, 1)}

    env = {
        "python": platform.python_version(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "system": f"{platform.system()} {platform.release()}",
        "detector": status["detector"]["component"]["name"],
        "door_sign": status["door_sign"]["component"]["name"],
        "item_matcher": status["item_matcher"]["component"]["name"],
        "images": [p.name for p in images],
    }
    print(json.dumps({"environment": env, "results": results}, indent=2))
    if args.json:
        args.json.write_text(json.dumps({"environment": env, "results": results}, indent=2))


if __name__ == "__main__":
    main()
