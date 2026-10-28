"""Verification of Google Sign-In ID tokens.

The Android app obtains an OpenID Connect ID token from Google for the
configured *web* client ID. The server verifies the token's signature against
Google's published certificates, its expiry, its issuer and its audience
before trusting any claim in it.
"""

from __future__ import annotations

from dataclasses import dataclass

from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


class GoogleTokenError(Exception):
    pass


@dataclass(frozen=True)
class GoogleIdentity:
    sub: str
    email: str
    email_verified: bool
    given_name: str
    family_name: str


class GoogleTokenVerifier:
    def __init__(self, client_ids: list[str]):
        self.client_ids = [c.strip() for c in client_ids if c.strip()]
        # Caches Google's certificates between requests.
        self._request = google_requests.Request()

    @property
    def configured(self) -> bool:
        return bool(self.client_ids)

    def verify(self, token: str) -> GoogleIdentity:
        try:
            claims = id_token.verify_oauth2_token(token, self._request, audience=self.client_ids,
                                                  clock_skew_in_seconds=10)
        except ValueError as exc:
            raise GoogleTokenError(str(exc)) from exc
        except Exception as exc:  # network failure fetching Google's certificates
            raise GoogleTokenError(f"Could not verify the token: {exc}") from exc
        if claims.get("iss") not in _ISSUERS:
            raise GoogleTokenError("Unexpected token issuer.")
        if not claims.get("sub") or not claims.get("email"):
            raise GoogleTokenError("The token has no account id or email.")
        return GoogleIdentity(
            sub=str(claims["sub"]),
            email=str(claims["email"]).lower(),
            email_verified=bool(claims.get("email_verified")),
            given_name=str(claims.get("given_name") or ""),
            family_name=str(claims.get("family_name") or ""),
        )
