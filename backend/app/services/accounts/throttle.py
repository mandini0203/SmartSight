"""Brute-force protection for password sign-in.

After ``max_failures`` failed attempts within ``window``, further attempts for
that key are refused until the window has passed. Keys are the account email
and the client address, so one attacker cannot try many passwords on one
account or many accounts from one address. State is kept in memory only: it
resets on restart and is not shared between server processes.
"""

from __future__ import annotations

import threading
import time
from collections import deque


class LoginThrottle:
    def __init__(self, max_failures: int, window_seconds: float, clock=time.monotonic):
        self.max_failures = max_failures
        self.window = window_seconds
        self._clock = clock
        self._failures: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def _recent(self, key: str) -> deque[float]:
        q = self._failures.setdefault(key, deque())
        cutoff = self._clock() - self.window
        while q and q[0] < cutoff:
            q.popleft()
        return q

    def retry_after(self, *keys: str) -> int:
        """Seconds until an attempt is allowed again; 0 when allowed now."""
        with self._lock:
            wait = 0.0
            for key in keys:
                q = self._recent(key)
                if len(q) >= self.max_failures:
                    wait = max(wait, q[0] + self.window - self._clock())
            return int(wait) + (1 if wait else 0)

    def record_failure(self, *keys: str) -> None:
        with self._lock:
            now = self._clock()
            for key in keys:
                self._recent(key).append(now)

    def reset(self, *keys: str) -> None:
        with self._lock:
            for key in keys:
                self._failures.pop(key, None)
