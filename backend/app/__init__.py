import os

# Ultralytics must never pip-install packages or send telemetry at runtime.
# Set before anything imports ultralytics.
os.environ.setdefault("YOLO_AUTOINSTALL", "False")
os.environ.setdefault("YOLO_OFFLINE", "True")

__version__ = "1.0.0"
