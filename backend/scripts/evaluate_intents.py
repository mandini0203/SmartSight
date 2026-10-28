"""Evaluate the rule-based intent resolver on a labelled phrase set.

Usage: python scripts/evaluate_intents.py [--data ../docs/evaluation/intent_phrases.jsonl]

The default phrase set was written by the developer and is NOT taken from
real users; it is kept separate from the unit-test phrases, but it is still
biased towards phrasings the rules anticipate. Treat its accuracy as an
optimistic baseline. A future trained resolver must be compared on held-out
phrases collected from real users.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.schemas.intent import IntentRequest  # noqa: E402
from app.services.intent.rule_based import RuleBasedIntentResolver  # noqa: E402


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--data", type=Path, default=ROOT.parent / "docs" / "evaluation" / "intent_phrases.jsonl")
    p.add_argument("--json", type=Path)
    args = p.parse_args()

    from ultralytics.utils import YAML  # COCO names without loading a model
    from ultralytics.utils import ROOT as UROOT

    names = list(YAML.load(UROOT / "cfg" / "datasets" / "coco.yaml")["names"].values())
    resolver = RuleBasedIntentResolver(names)

    rows = [json.loads(line) for line in args.data.read_text(encoding="utf-8").splitlines() if line.strip()]
    correct_intent = correct_full = 0
    confusion: Counter = Counter()
    failures = []
    for row in rows:
        r = resolver.resolve(IntentRequest(text=row["text"]))
        exp_status = row.get("status", "RESOLVED")
        got_intent = r.intent.value if r.intent else None
        intent_ok = got_intent == row["intent"]
        full_ok = intent_ok and r.status.value == exp_status and r.slots.target_label == row["label"]
        correct_intent += intent_ok
        correct_full += full_ok
        confusion[(row["intent"], got_intent)] += 1
        if not full_ok:
            failures.append({"text": row["text"], "expected": [row["intent"], exp_status, row["label"]],
                             "got": [got_intent, r.status.value, r.slots.target_label]})

    n = len(rows)
    report = {
        "phrases": n,
        "intent_accuracy": round(correct_intent / n, 3),
        "full_accuracy_intent_status_slot": round(correct_full / n, 3),
        "failures": failures,
        "confusion": {f"{e} -> {g}": c for (e, g), c in sorted(confusion.items(), key=str)},
        "note": "Developer-written phrases; optimistic baseline, not a user study.",
    }
    print(json.dumps(report, indent=2))
    if args.json:
        args.json.write_text(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
