# API fixtures

These JSON files are **real responses** recorded from the SmartSight backend
(actual YOLOv8 / YOLO-World inference on the Ultralytics sample images
`bus.jpg` and `zidane.jpg`). They are used by the Dart contract tests so the
app's parsers are checked against what the API really returns.

Regenerate after changing backend schemas:

    cd backend
    .venv/Scripts/python scripts/export_contract_fixtures.py   # Windows
    .venv/bin/python scripts/export_contract_fixtures.py       # macOS/Linux

`context_seats.json` uses hand-written detections as *input* to exercise the
seat rules; its output is the real rule engine's response.
