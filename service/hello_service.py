#!/usr/bin/env python3
"""hello service — a relying party that follows the external-service rules.

This is the service side of goat's external service golden path (ADR 1178).
The goatnet lends the sign-in;
this program verifies the tokens itself and authorizes from its OWN records.
The trust rule, in one line: the provider authenticates, the service
authorizes, and a token's claims grant nothing on their own.

The rules, in the order they run on every request to /api/*:

  1. `Authorization: Bearer <id_token>` is present            else 401
  2. the signature verifies against the issuer's JWKS         else 401
  3. `iss` equals HELLO_ISSUER exactly, trailing slash and all else 401
  4. `aud` equals HELLO_CLIENT_ID (the declaration's client.id) else 401
  5. `exp` is in the future                                     else 401
  6. the token carries `email`                                  else 401
  7. `email_verified` is not false                              else 403
  8. the email is on the roster (service/roster.json)           -> 200
     when it is not:
       AUTO_ROSTER_VENDORS=true and the token carries aff.id and the org
       snapshot lists that org as kind=vendor status=active and the snapshot
       is younger than SNAPSHOT_MAX_AGE_SECONDS   -> rostered now, 200
       anything else                              -> 403, fail closed
  9. when the token's aff.id disagrees with the roster row's org, an
     `org_mismatch` audit line is written and the request is still admitted:
     the roster decides, the claim is evidence.

Every refusal names who can fix it. /healthz is open (no session), because the
goatnet's pre-flight and status page probe it. GET /api/me returns the principal.

Configuration (environment):
  HELLO_BIND                    default 127.0.0.1. On a real host: the MESH IP,
                                never 0.0.0.0 (mesh membership is the outer gate).
  HELLO_PORT                    default 9402
  HELLO_ISSUER                  the issuer URL the goatnet printed back, WITH trailing slash
  HELLO_JWKS_URL                default HELLO_ISSUER + ".well-known/jwks.json"
  HELLO_CLIENT_ID               the declaration's client.id
  HELLO_ROSTER_FILE             default service/roster.json (rewritten on auto-roster)
  HELLO_ORG_SNAPSHOT_FILE       default service/org-snapshot.json (re-read per request)
  HELLO_AUTO_ROSTER_VENDORS     true|false, default false
  HELLO_SNAPSHOT_MAX_AGE_SECONDS default 86400
  HELLO_OWNER                   who to name in refusals, default "the service owner"

Dependencies: PyJWT + cryptography (requirements.txt). Standard-library HTTP.
"""
import datetime
import json
import os
import sys
import threading
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import jwt


def env(name, default=None):
    v = os.environ.get(name)
    return v if v not in (None, "") else default


CFG = {
    "bind": env("HELLO_BIND", "127.0.0.1"),
    "port": int(env("HELLO_PORT", "9402")),
    "issuer": env("HELLO_ISSUER"),
    "jwks_url": env("HELLO_JWKS_URL"),
    "client_id": env("HELLO_CLIENT_ID"),
    "roster_file": env("HELLO_ROSTER_FILE", os.path.join(os.path.dirname(__file__), "roster.json")),
    "snapshot_file": env("HELLO_ORG_SNAPSHOT_FILE", os.path.join(os.path.dirname(__file__), "org-snapshot.json")),
    "auto_roster_vendors": (env("HELLO_AUTO_ROSTER_VENDORS", "false").lower() == "true"),
    "snapshot_max_age": int(env("HELLO_SNAPSHOT_MAX_AGE_SECONDS", "86400")),
    "owner": env("HELLO_OWNER", "the service owner"),
}

LOCK = threading.Lock()


def log(kind, **fields):
    line = kind + " " + " ".join("%s=%s" % (k, json.dumps(v) if not isinstance(v, str) else v)
                                 for k, v in fields.items())
    sys.stderr.write(line + "\n")
    sys.stderr.flush()


class Refusal(Exception):
    def __init__(self, status, reason, fix):
        super().__init__(reason)
        self.status, self.reason, self.fix = status, reason, fix


# ---- the issuer's keys ------------------------------------------------------
class Jwks:
    def __init__(self, url):
        self.url = url
        self.keys = {}

    def refresh(self):
        with urllib.request.urlopen(self.url, timeout=5) as r:
            doc = json.load(r)
        self.keys = {k["kid"]: jwt.PyJWK(k).key for k in doc.get("keys", []) if "kid" in k}

    def key_for(self, kid):
        if kid not in self.keys:
            self.refresh()  # an unknown kid is what a key rotation looks like
        return self.keys.get(kid)


JWKS = None


# ---- the service's own records ----------------------------------------------
def load_roster():
    with open(CFG["roster_file"]) as f:
        doc = json.load(f)
    return doc


def save_roster(doc):
    tmp = CFG["roster_file"] + ".tmp"
    with open(tmp, "w") as f:
        json.dump(doc, f, indent=2)
    os.replace(tmp, CFG["roster_file"])


def roster_lookup(doc, email):
    for row in doc.get("entries", []):
        if row.get("email", "").lower() == email.lower():
            return row
    return None


def load_snapshot():
    """Returns (orgs-by-id, age-seconds). Re-read on every call: the file is
    what the operator refreshes, and a cached copy would hide a stale one."""
    with open(CFG["snapshot_file"]) as f:
        doc = json.load(f)
    stamp = datetime.datetime.strptime(doc["generated_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    age = (datetime.datetime.now(datetime.timezone.utc) - stamp).total_seconds()
    return {o["id"]: o for o in doc.get("orgs", [])}, int(age)


# ---- the rules ------------------------------------------------------------------
def verify(token):
    """Rules 2 to 6. Returns the verified claims or raises Refusal(401)."""
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError as e:
        raise Refusal(401, "the bearer token is not a JWT (%s)" % e,
                      "sign in again through the service's fence; if it repeats, %s checks the fence forwards the id_token, not the access token" % CFG["owner"])
    key = JWKS.key_for(header.get("kid"))
    if key is None:
        raise Refusal(401, "the token's signing key (kid %s) is not in the issuer's JWKS" % header.get("kid"),
                      "%s checks HELLO_JWKS_URL is the jwks line the goatnet printed back" % CFG["owner"])
    try:
        claims = jwt.decode(
            token, key, algorithms=["RS256"],
            audience=CFG["client_id"], issuer=CFG["issuer"],
            options={"require": ["exp", "iss", "aud", "sub"]},
        )
    except jwt.ExpiredSignatureError:
        raise Refusal(401, "the token has expired",
                      "sign in again; if this happens under a live session, %s pins client.token_lifespan in the declaration to the fence's cookie lifetime" % CFG["owner"])
    except jwt.InvalidIssuerError:
        iss = jwt.decode(token, options={"verify_signature": False}).get("iss")
        raise Refusal(401, "the token's issuer %r is not the configured issuer %r (exact string match, trailing slash included)" % (iss, CFG["issuer"]),
                      "%s sets HELLO_ISSUER to the issuer line the goatnet printed back, slash and all" % CFG["owner"])
    except jwt.InvalidAudienceError:
        aud = jwt.decode(token, options={"verify_signature": False}).get("aud")
        raise Refusal(401, "the token's audience %r is not this service's client id %r" % (aud, CFG["client_id"]),
                      "%s sets HELLO_CLIENT_ID to client.id in the declaration; the fence must use the same client" % CFG["owner"])
    except jwt.InvalidSignatureError:
        raise Refusal(401, "the token's signature does not verify against the issuer's JWKS",
                      "%s checks HELLO_JWKS_URL points at the goatnet's issuer, not another one" % CFG["owner"])
    except jwt.MissingRequiredClaimError as e:
        raise Refusal(401, "the token lacks a required claim: %s" % e,
                      "%s checks the fence forwards the id_token" % CFG["owner"])
    except jwt.PyJWTError as e:
        raise Refusal(401, "the token did not verify: %s" % e, "sign in again")
    if not isinstance(claims.get("email"), str) or "@" not in claims["email"]:
        raise Refusal(401, "the token carries no email claim",
                      "%s adds `email` to client.scopes in the declaration and has it re-applied" % CFG["owner"])
    return claims


def authorize(claims):
    """Rules 7 to 9. Returns the principal or raises Refusal(403)."""
    email = claims["email"]
    if claims.get("email_verified") is False:
        raise Refusal(403, "your email address is not verified",
                      "the goatnet's identity admins verify the identity at the identity provider; the service cannot")
    token_org = (claims.get("aff") or {}).get("id") if isinstance(claims.get("aff"), dict) else None
    with LOCK:
        roster = load_roster()
        row = roster_lookup(roster, email)
        source = "roster"
        if row is None:
            row = auto_roster(roster, email, token_org)
            source = "auto-vendor"
    if token_org and row.get("org") and token_org != row["org"]:
        log("audit", event="org_mismatch", email=email, token_org=token_org, roster_org=row["org"],
            decision="admitted (the roster decides; the claim is evidence)")
    return {
        "email": email,
        "email_verified": claims.get("email_verified"),
        "sub": claims.get("sub"),
        "groups": claims.get("groups", []),
        "org": row.get("org"),
        "role": row.get("role"),
        "roster_source": source,
        "token_org": token_org,
    }


def auto_roster(roster, email, token_org):
    not_on = "authenticated but not on the roster"
    if not CFG["auto_roster_vendors"]:
        raise Refusal(403, not_on, "%s adds %s to roster.json" % (CFG["owner"], email))
    if not token_org:
        raise Refusal(403, not_on + " (the token carries no aff.id to roster from)",
                      "%s adds %s to roster.json" % (CFG["owner"], email))
    orgs, age = load_snapshot()
    if age > CFG["snapshot_max_age"]:
        raise Refusal(403, not_on + " (vendor auto-roster is off: the org snapshot is %ds old, older than %ds)" % (age, CFG["snapshot_max_age"]),
                      "%s refreshes org-snapshot.json from the goat registry, or adds %s to roster.json" % (CFG["owner"], email))
    org = orgs.get(token_org)
    if org is None or org.get("kind") != "vendor" or org.get("status") != "active":
        what = ("is not in the org snapshot" if org is None
                else "is kind=%s status=%s, not an active vendor" % (org.get("kind"), org.get("status")))
        raise Refusal(403, not_on + " (aff.id %s %s)" % (token_org, what),
                      "%s adds %s to roster.json, or refreshes the org snapshot if %s should be an active vendor" % (CFG["owner"], email, token_org))
    row = {"email": email, "org": token_org, "role": "vendor", "source": "auto-vendor",
           "added_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    roster.setdefault("entries", []).append(row)
    save_roster(roster)
    log("audit", event="auto_rostered", email=email, org=token_org, org_name=org.get("name", ""), snapshot_age_s=age)
    return row


# ---- HTTP ---------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    server_version = "hello-external-service/1"

    def _json(self, code, body):
        data = (json.dumps(body, indent=2) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path == "/healthz":
            self._json(200, {"ok": True, "service": "hello", "auth": "none on this path"})
            log("access", path=self.path, status=200)
            return
        if not self.path.startswith("/api/"):
            self._json(404, {"error": "not found"})
            return
        auth = self.headers.get("Authorization", "")
        try:
            if not auth.startswith("Bearer "):
                raise Refusal(401, "no bearer token",
                              "sign in through the service's fence; it forwards the goatnet's id_token as a bearer")
            claims = verify(auth[len("Bearer "):].strip())
            principal = authorize(claims)
        except Refusal as r:
            self._json(r.status, {"error": r.reason, "who_can_fix_it": r.fix})
            log("access", path=self.path, status=r.status, reason=json.dumps(r.reason))
            return
        if self.path == "/api/me":
            self._json(200, {"principal": principal, "service": "hello"})
        else:
            self._json(404, {"error": "not found", "principal": principal["email"]})
        log("access", path=self.path, status=200, email=principal["email"], source=principal["roster_source"])


def main():
    global JWKS
    missing = [k for k in ("issuer", "client_id") if not CFG[k]]
    if missing:
        sys.exit("hello_service: set HELLO_ISSUER and HELLO_CLIENT_ID (the goatnet prints both)")
    if not CFG["issuer"].endswith("/"):
        sys.stderr.write("hello_service: WARNING HELLO_ISSUER has no trailing slash; the goatnet's `iss` claim carries one, so every token will be refused\n")
    if CFG["bind"] == "0.0.0.0":
        sys.exit("hello_service: refusing to bind 0.0.0.0 — bind the host's mesh IP; mesh membership is the outer gate")
    CFG["jwks_url"] = CFG["jwks_url"] or (CFG["issuer"] + ".well-known/jwks.json")
    JWKS = Jwks(CFG["jwks_url"])
    log("start", bind=CFG["bind"], port=CFG["port"], issuer=CFG["issuer"], jwks=CFG["jwks_url"],
        client_id=CFG["client_id"], auto_roster_vendors=CFG["auto_roster_vendors"],
        snapshot_max_age_s=CFG["snapshot_max_age"])
    srv = ThreadingHTTPServer((CFG["bind"], CFG["port"]), Handler)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
