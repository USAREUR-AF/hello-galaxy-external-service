#!/usr/bin/env python3
"""A SIMULATED OpenID Connect issuer for the laptop.

This stands in for the goatnet's site Hydra (Ory Hydra) so the hello service
can be exercised without a goatnet. It is NOT Hydra and does no login flow:
`POST /mint` hands out an id_token for whatever claims the caller asks for.
That is the one and only thing a real issuer would never do, and it is why
this program lives under local-issuer/ and is graded SIMULATED in
docs/honesty-matrix.md.

What it does faithfully, so the service's verification code is real:

  * generates a fresh RS256 keypair at start and publishes it as a JWK
  * serves /.well-known/openid-configuration and /.well-known/jwks.json
  * signs id_tokens whose `iss` is its own base URL WITH a trailing slash,
    the way Hydra's issuer URL is configured on a goatnet
    (https://oauth2.<site>.<zone>/). The slash is part of the string the
    relying party compares exactly.

Mint request (JSON body):
  {
    "email": "...",              required
    "email_verified": true,      default true
    "aff": {"id": "org-..."},    optional; goat's affiliation claim
    "groups": ["..."],           default []
    "aud": "<client id>",        default "oauth2-proxy-hello-external"
    "sub": "...",                default derived from email
    "exp_seconds": 3600,         default 3600; negative = already expired
    "iss": "http://..."          OVERRIDE, demo only: lets a scenario show what
                                 happens when `iss` lacks the trailing slash
  }
Reply: {"id_token": "<jwt>", "claims": {...}}

Dependencies: PyJWT + cryptography (requirements.txt).
"""
import argparse
import datetime
import hashlib
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

DEFAULT_AUD = "oauth2-proxy-hello-external"


class Issuer:
    def __init__(self, base_url):
        if not base_url.endswith("/"):
            raise SystemExit("issuer base URL must end with a trailing slash (it is part of `iss`)")
        self.base_url = base_url
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        self.private_pem = key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        jwk = jwt.algorithms.RSAAlgorithm.to_jwk(key.public_key(), as_dict=True)
        self.kid = hashlib.sha256(json.dumps(jwk, sort_keys=True).encode()).hexdigest()[:16]
        jwk.update({"kid": self.kid, "use": "sig", "alg": "RS256"})
        self.jwks = {"keys": [jwk]}

    def discovery(self):
        b = self.base_url
        return {
            "issuer": b,
            "jwks_uri": b + ".well-known/jwks.json",
            "authorization_endpoint": b + "oauth2/auth",
            "token_endpoint": b + "oauth2/token",
            "id_token_signing_alg_values_supported": ["RS256"],
            "response_types_supported": ["code"],
            "scopes_supported": ["openid", "profile", "email", "groups"],
            "subject_types_supported": ["public"],
            "_simulated": "hello-galaxy local issuer; not Ory Hydra; no login flow",
        }

    def mint(self, req):
        email = req.get("email")
        if not isinstance(email, str) or "@" not in email:
            raise ValueError("email is required")
        now = datetime.datetime.now(datetime.timezone.utc)
        exp_seconds = int(req.get("exp_seconds", 3600))
        claims = {
            "iss": req.get("iss", self.base_url),
            "sub": req.get("sub") or hashlib.sha256(email.lower().encode()).hexdigest()[:32],
            "aud": req.get("aud", DEFAULT_AUD),
            "iat": int(now.timestamp()),
            "exp": int((now + datetime.timedelta(seconds=exp_seconds)).timestamp()),
            "email": email,
            "email_verified": bool(req.get("email_verified", True)),
            "groups": list(req.get("groups", [])),
        }
        if "aff" in req and req["aff"] is not None:
            claims["aff"] = req["aff"]
        token = jwt.encode(claims, self.private_pem, algorithm="RS256", headers={"kid": self.kid})
        return {"id_token": token, "claims": claims}


def make_handler(issuer):
    class Handler(BaseHTTPRequestHandler):
        server_version = "hello-galaxy-local-issuer/1"

        def _json(self, code, body):
            data = json.dumps(body, indent=2).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, fmt, *args):
            sys.stderr.write("issuer %s - %s\n" % (self.address_string(), fmt % args))

        def do_GET(self):
            if self.path == "/.well-known/openid-configuration":
                return self._json(200, issuer.discovery())
            if self.path == "/.well-known/jwks.json":
                return self._json(200, issuer.jwks)
            if self.path == "/":
                return self._json(200, {"simulated_issuer": issuer.base_url, "mint": "POST /mint"})
            return self._json(404, {"error": "not found"})

        def do_POST(self):
            if self.path != "/mint":
                return self._json(404, {"error": "not found"})
            n = int(self.headers.get("Content-Length") or 0)
            try:
                req = json.loads(self.rfile.read(n) or b"{}")
                return self._json(200, issuer.mint(req))
            except (ValueError, TypeError) as e:
                return self._json(400, {"error": str(e)})

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=9401)
    ap.add_argument("--issuer", default=None,
                    help="base URL to put in `iss` (default http://<bind>:<port>/; must end with /)")
    a = ap.parse_args()
    base = a.issuer or "http://%s:%d/" % (a.bind, a.port)
    issuer = Issuer(base)
    srv = ThreadingHTTPServer((a.bind, a.port), make_handler(issuer))
    sys.stderr.write("issuer: SIMULATED OIDC issuer at %s (kid %s)\n" % (base, issuer.kid))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
