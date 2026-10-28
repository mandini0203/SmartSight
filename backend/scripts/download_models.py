"""Download and verify every pretrained weight file the backend uses.

Usage (from the backend directory):
    python scripts/download_models.py            # all models
    python scripts/download_models.py --only yolov8n

Files are written under backend/models/ and checked against SHA-256 hashes.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.request
from pathlib import Path

MODELS_DIR = Path(__file__).resolve().parent.parent / "models"

MODELS = {
    "yolov8n": (
        "https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.pt",
        MODELS_DIR / "yolov8n.pt",
        "f59b3d833e2ff32e194b5bb8e08d211dc7c5bdf144b90d2c8412c47ccfc83b36",
    ),
    "yolov8s-worldv2": (
        "https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8s-worldv2.pt",
        MODELS_DIR / "yolov8s-worldv2.pt",
        "9b2c17ab6124a913e9b3a5c170617920d91b0f01111a8479da69f00e2cf27792",
    ),
    "clip-vit-b32": (
        "https://openaipublic.azureedge.net/clip/models/"
        "40d365715913c9da98579312b702a82c18be219cc2a73407c4526f58eba950af/ViT-B-32.pt",
        MODELS_DIR / "clip" / "ViT-B-32.pt",
        "40d365715913c9da98579312b702a82c18be219cc2a73407c4526f58eba950af",
    ),
    "mobilenet_v3_small": (
        "https://download.pytorch.org/models/mobilenet_v3_small-047dcff4.pth",
        MODELS_DIR / "torch" / "hub" / "checkpoints" / "mobilenet_v3_small-047dcff4.pth",
        "047dcff4addef86ea5bc2eff13c9614dc11f47ab1160d0a71a25e7db994f4e1f",
    ),
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(name: str) -> bool:
    url, dest, expected = MODELS[name]
    if dest.is_file() and sha256(dest) == expected:
        print(f"[ok]   {name} already present ({dest.relative_to(MODELS_DIR.parent)})")
        return True
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    print(f"[get]  {name} <- {url}")
    urllib.request.urlretrieve(url, tmp)
    actual = sha256(tmp)
    if actual != expected:
        tmp.unlink(missing_ok=True)
        print(f"[FAIL] {name}: checksum mismatch ({actual})", file=sys.stderr)
        return False
    tmp.replace(dest)
    print(f"[ok]   {name} saved to {dest.relative_to(MODELS_DIR.parent)}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", choices=sorted(MODELS), action="append")
    args = parser.parse_args()
    names = args.only or list(MODELS)
    return 0 if all(fetch(n) for n in names) else 1


if __name__ == "__main__":
    raise SystemExit(main())
