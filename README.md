# SmartSight

SmartSight is an assistive camera app for blind and partially sighted users. It can:

- describe surroundings
- find personal belongings
- locate exit signs and doors
- estimate where objects are and how far away
- identify colours
- give task-specific spoken guidance, controlled by voice or touch

| Part | Technology | Folder |
|---|---|---|
| Android app | Flutter 3.44 / Dart 3.12, Material 3 | `frontend/` |
| Backend API | Python 3.13, FastAPI, Pydantic v2 | `backend/` |
| Object detection | **pretrained YOLOv8n** (COCO, 80 classes), not fine-tuned | `backend/models/yolov8n.pt` |
| Doors / exit signs | pretrained YOLOv8s-World v2 (open vocabulary) + colour/shape checks | `backend/models/yolov8s-worldv2.pt` |
| Intent + context | deterministic **rule-based** baselines (not trained models) | `backend/app/services/{intent,context}` |

> **Safety.** SmartSight is an assistive information system. It is **not** a
> certified replacement for a cane, guide dog or other mobility aid. All outputs
> are estimates and can be wrong due to some environmental changes and device
> quality and condition.

Further documentation:

- [Setup and run guide](docs/SETUP_AND_RUN.md) — requirements, installs, running backend and app, full tech stack
- [API reference](docs/API.md)
- [Architecture & decisions](docs/ARCHITECTURE.md)
- [Context rules](docs/CONTEXT_RULES.md)
- [Distance estimation](docs/DISTANCE_ESTIMATION.md)
- [Future model integration](docs/MODEL_INTEGRATION.md)
- [Evaluation & results](docs/EVALUATION.md)
- [Requirements](docs/REQUIREMENTS.md)

---

## 1. Backend setup

Requirements: Python 3.11+ (tested with 3.13). A GPU is optional; CPU works.

```bash
cd backend
python -m venv .venv
# Windows
.venv\Scripts\activate
# macOS / Linux
source .venv/bin/activate

pip install -r requirements-dev.txt          # includes pytest; use requirements.txt for production
python scripts/download_models.py            # ~380 MB, verified by SHA-256
cp .env.example .env                         # optional; all settings have defaults
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

* Swagger UI: <http://localhost:8000/docs>. Health check: `curl http://localhost:8000/health`.
* Model readiness: `curl http://localhost:8000/api/v1/status`. `status` is `ok`, or
  `degraded` if a fallback is being used (see `load_errors`).
* For a CUDA GPU, install the matching torch wheel from pytorch.org and set
  `SMARTSIGHT_INFERENCE_DEVICE=0`.

### Model files

| File | Source | SHA-256 (prefix) | Used for |
|---|---|---|---|
| `models/yolov8n.pt` | ultralytics/assets v8.3.0 | `f59b3d83…` | object detection, 80 COCO classes |
| `models/yolov8s-worldv2.pt` | ultralytics/assets v8.3.0 | `9b2c17ab…` | "door" / "exit sign" text-prompted detection |
| `models/clip/ViT-B-32.pt` | OpenAI CLIP | `40d36571…` | text encoder for YOLO-World prompts (load time only) |
| `models/torch/hub/checkpoints/mobilenet_v3_small-047dcff4.pth` | torchvision | `047dcff4…` | image embeddings for personal-item matching |

**Licences.** Ultralytics YOLOv8 and its weights are **AGPL-3.0**. They are fine
for this academic project, but distributing a closed-source product or service
requires complying with AGPL-3.0 or buying an Ultralytics Enterprise licence.
CLIP is MIT. The torchvision weights are BSD-3-Clause. COCO annotations are CC BY 4.0.

**What the detector can recognise.** Only the 80 COCO classes
(`GET /api/v1/detection/classes`), for example person, chair, couch, bench,
dining table, cell phone, laptop, cup, bottle, backpack, handbag, book and remote.
It **cannot** recognise keys, wallets, glasses, doors or exit signs. The app
says so rather than guessing. Doors and exit signs go through the separate
YOLO-World detector.

**Inference requirements.** About 1.5 GB RAM with all models loaded. Start-up
takes about 45 s on a laptop CPU. Warm latency is about 180 ms per detection
on CPU (see `docs/EVALUATION.md`).

### Environment variables

All settings are optional and prefixed `SMARTSIGHT_`. See `backend/.env.example`.

| Variable | Default | Purpose |
|---|---|---|
| `MODEL_PATH` | `models/yolov8n.pt` | YOLOv8 checkpoint |
| `DETECTION_CONFIDENCE` / `DETECTION_IOU` / `DETECTION_IMAGE_SIZE` | 0.35 / 0.45 / 640 | inference parameters |
| `INFERENCE_DEVICE` | `cpu` | `cpu`, `0` (CUDA), `mps` |
| `INFERENCE_TIMEOUT_SECONDS` | 20 | per-request limit (→ 504) |
| `DOOR_SIGN_BACKEND` | `yolo_world` | or `heuristic` (OpenCV, exit signs only, no model) |
| `ITEM_MATCHER` | `embedding` | or `orb` (no download) |
| `ITEM_MATCH_THRESHOLD` / `ITEM_POSSIBLE_MATCH_THRESHOLD` | 0.80 / 0.65 | uncalibrated defaults |
| `CAMERA_FOV_DEGREES` | 66 | field of view across the long image side, for distances |
| `MAX_UPLOAD_BYTES` / `MAX_IMAGE_SIDE` | 8 MB / 6000 | upload limits |
| `LOG_LEVEL`, `CORS_ORIGINS`, `WARMUP_ON_STARTUP` | INFO, [], true | |

### Backend tests and evaluation

```bash
cd backend
.venv/Scripts/python -m pytest                       # 119 tests, real inference (≈1–2 min)
python scripts/benchmark.py --runs 20                # needs the server running
python scripts/evaluate_intents.py
python scripts/evaluate_scenarios.py                 # needs the server running
python scripts/evaluate_item_matching.py items/ --label "cell phone"   # with your own photos
python scripts/export_contract_fixtures.py           # refresh Flutter test fixtures after API changes
```

---

## 2. Frontend setup (Android)

Requirements: Flutter 3.44+, Android SDK with platform 37, and a device or emulator
running Android 7.0+ with a camera.

```bash
cd frontend
flutter pub get
flutter run                                   # debug on a connected device / emulator
flutter build apk --debug                     # build/app/outputs/flutter-apk/app-debug.apk
```

**Server address.**

* The Android emulator reaches your computer at `http://10.0.2.2:8000`. This is the default.
* On a real phone, use your computer's LAN address, for example
  `http://192.168.1.20:8000`. Enter it in **Settings → SmartSight server address →
  Save and test connection**, or build with
  `flutter run --dart-define=SMARTSIGHT_BACKEND_URL=http://192.168.1.20:8000`.
* Debug builds allow plain HTTP on any address
  (`android/app/src/debug/res/xml/network_security_config.xml`). Release builds
  allow cleartext only to the emulator host, so put the backend behind
  **HTTPS** for real deployments.

### Using the app

* **Home**: Smart Scan, My Items, Doors and Signs, Colour Finder, Settings, and a
  "Type a request" box.
* Every screen has **Speak command** and **Repeat** at the bottom.
* **App voice commands** are interpreted on the phone and work offline:
  - navigation: "smart scan", "my items", "doors and signs", "colour finder",
    "settings", "home" / "dashboard", "go back"
  - control: "capture" / "analyse now", "start", "pause", "resume", "stop", "repeat"
  - "help"
  - navigation phrases also work after a verb: "open …", "go to …", "take me to …"
* **Task requests** go to the backend: "find my phone", "where is the exit",
  "find a place to sit", "what colour is this", "describe my surroundings".
* **Capture-and-analyse** is the default. **Start** begins continuous guidance:
  one photo every 4 s by default, at most one photo in flight. Results older than
  8 s are discarded and never presented as current.
* **My Items**: register an item with a name, a type (detector class) and 1–5
  reference photos, each quality-checked by the server. For guests, photos stay
  on the phone and are only sent with a search request. For signed-in users,
  items are also saved in their account on the server.
* **Accounts (optional)**: register with email and password or continue with
  Google, or use the app as a guest. Registration asks for name, NIC (birthday,
  age and gender are filled in from it), address, mobile and WhatsApp number,
  optional BMI and eyesight level. Every field can be spoken. See
  [Setup guide §5.1](docs/SETUP_AND_RUN.md#51-user-accounts-and-google-sign-in)
  and the [API reference](docs/API.md#user-accounts).
* **Settings**: server address, speech rate, voice mode (automatic uses TalkBack
  announcements when TalkBack is on), detailed guidance, vibration, scan
  interval, stale-result threshold, and camera field of view.

### Frontend tests

```bash
cd frontend
flutter analyze
flutter test                                  # 246 tests: unit, widget, navigation, accessibility
# Real end-to-end client test against a running backend:
SMARTSIGHT_LIVE_BACKEND=http://127.0.0.1:8000 \
SMARTSIGHT_TEST_IMAGES=<python site-packages>/ultralytics/assets \
flutter test test/integration/live_backend_test.dart
```

---

## 3. Project structure

```
backend/
  app/main.py              FastAPI app factory, routers, error handlers
  app/config.py            env-var settings (pydantic-settings)
  app/errors.py            consistent error responses
  app/logging_config.py    privacy-aware request logging
  app/schemas/             Pydantic request/response models
  app/api/routes/          health, detection, scan+context, intent, items, colour, signs
  app/services/
    interfaces.py          ObjectDetector, IntentResolver, ContextReasoner, PersonalItemMatcher,
                           ColourIdentifier, DistanceEstimator, DoorSignDetector
    registry.py            builds implementations from config; bounded inference queue
    detection/ context/ intent/ items/ colour/ signs/ spatial.py distance.py
  scripts/                 model download, benchmark, evaluations, fixture export
  tests/                   pytest suite (real inference)
frontend/
  lib/main.dart, lib/app/  app, router, theme
  lib/core/                api client & models, voice, guidance, camera, feedback, storage, permissions
  lib/features/            home, scan, items, doors_signs, colour, settings
  lib/shared/              scaffold, voice bar, camera panel, controls, result widgets
  test/                    unit, widget, navigation, accessibility, integration; fixtures from the real API
docs/                      API, architecture, rules, distance, model integration, evaluation, results
```

---

## 4. Status: complete, partial and not done

**Implemented and tested:** both applications and their integration over HTTP:

- real YOLOv8 inference
- door/exit-sign candidates
- rule-based intent resolution, context reasoning, seat assessment, relative
  position and distance estimates
- colour identification
- personal-item registration and embedding-based matching
- voice and touch control, TTS / TalkBack and haptics
- offline and stale-result handling, accessibility checks
- benchmarks and scenario evaluation

**Known limitations:**

* Detection is limited to 80 COCO classes. Small objects (ties, phones far
  away) are often missed at the 0.35 threshold.
* Door/exit-sign detection is open-vocabulary and not fine-tuned. Confirmed false
  positive: a bus destination display is reported as a weak exit candidate.
* Thresholds for item matching, seat rules and distances have **not** been
  calibrated on real user data. Accuracy for these is unmeasured
  (`docs/EVALUATION.md` §6).
* No on-device inference: the app needs the backend on the same network or
  reachable over HTTPS.
* The app was built and its logic tested with fakes and recorded real API
  responses, and the client was tested live against the backend. On-device
  testing with a physical camera, TalkBack and real users is still required.
* English only. Portrait orientation only.

---

## 5. Troubleshooting

| Problem | Fix |
|---|---|
| App banner "Server unavailable" | Check the backend is running with `--host 0.0.0.0`, that the phone and computer are on the same network, and that the address is right in Settings. Allow port 8000 in the Windows firewall. |
| Emulator cannot connect | Use `http://10.0.2.2:8000`, not `localhost`. |
| `/api/v1/status` reports `degraded` | Read `load_errors`. Usually a missing weight file: run `python scripts/download_models.py`. |
| 503 "server is busy" | More than four requests were waiting. Increase the scan interval in Settings or use a faster machine or GPU. |
| 504 timeouts | The CPU is overloaded. Raise `SMARTSIGHT_INFERENCE_TIMEOUT_SECONDS` or reduce `SMARTSIGHT_DETECTION_IMAGE_SIZE`. |
| `ModuleNotFoundError: clip` | `pip install -r requirements.txt` (installs CLIP from GitHub), or set `SMARTSIGHT_DOOR_SIGN_BACKEND=heuristic`. |
| Android build: "requires compileSdk 37" | Install Android SDK Platform 37 (`compileSdk = 37` is set in `android/app/build.gradle.kts`). |
| Voice commands do nothing | Grant the microphone permission and install or enable Google speech services on the device. |
| Speech talks over TalkBack | Settings → Voice → Automatic or "Always use screen reader announcements". |
| Distances look wrong | Calibrate the camera field of view (`docs/DISTANCE_ESTIMATION.md`) and set it in Settings. |
