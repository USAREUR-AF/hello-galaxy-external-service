#!/usr/bin/env bash
# Scenario 02 — Sign in and authorize: every relying-party rule, with real tokens.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/hello-external.sh"
hx_preflight || exit 1

hx_banner "Sign in and authorize — the provider authenticates, the service authorizes" \
          "A simulated issuer mints tokens; the real service code decides on each one."

ROSTER="$HX_RUN/roster.json"; SNAP="$HX_RUN/org-snapshot.json"
cp service/roster.json "$ROSTER"
hx_snapshot "$SNAP" 0
: > "$HX_RUN/service.log"

hx_step "Start the simulated issuer and the hello service"
hx_honest "local-issuer/issuer.py stands in for the goatnet's Ory Hydra: it signs whatever"
hx_honest "claims it is asked for. service/hello_service.py is the real relying-party code."
hx_start_issuer || exit 1
hx_start_service "$ROSTER" "$SNAP" || exit 1
hx_say "service config: issuer=$HX_ISSUER  aud=$HX_CLIENT_ID  auto-roster vendors=on  snapshot max age=86400s"
hx_say "roster before:"; "$HX_PY" -c 'import json,sys; [print("   ", r["email"], r["org"], r["role"]) for r in json.load(open(sys.argv[1]))["entries"]]' "$ROSTER"

hx_step "/healthz is open (the goatnet's pre-flight and status page probe it)"
S="$(curl -sS -o /dev/null -w '%{http_code}' "$HX_SERVICE/healthz")"
hx_assert "GET /healthz -> $S without any token" test "$S" = 200

hx_step "(a) rostered vendor, verified email -> 200 and the principal"
T="$(hx_mint '{"email":"vendor.one@acme-drones.example","aff":{"id":"org-acme-drones"},"groups":["ZAGROS-VENDOR"]}')"
hx_call "$T"; hx_expect a 200 "rostered, verified: admitted; /api/me names the principal from the ROSTER row"

hx_step "(b) email_verified: false -> 403"
T="$(hx_mint '{"email":"vendor.one@acme-drones.example","email_verified":false}')"
hx_call "$T"; hx_expect b 403 "an unverified email is refused even though the person is rostered; the fix is at the identity provider"

hx_step "(c) unrostered, aff.id names an ACTIVE VENDOR in a FRESH snapshot -> auto-rostered 200"
T="$(hx_mint '{"email":"new.engineer@bluefield-sensors.example","aff":{"id":"org-bluefield-sensors"}}')"
hx_call "$T"; hx_expect c 200 "not on the roster, but the org snapshot vouches for org-bluefield-sensors: rostered now"
hx_assert "an auto_rostered audit line was written" hx_audit auto_rostered; hx_audit_show auto_rostered
hx_say "roster after (the service wrote the new row):"; "$HX_PY" -c 'import json,sys; [print("   ", r["email"], r["org"], r["role"]) for r in json.load(open(sys.argv[1]))["entries"]]' "$ROSTER"

hx_step "(d) unrostered, aff.id names an org the snapshot does not know -> 403, fail closed"
T="$(hx_mint '{"email":"someone@unknown-org.example","aff":{"id":"org-nobody-knows"}}')"
hx_call "$T"; hx_expect d 403 "authenticated but not on the roster; the claim alone grants nothing"
T="$(hx_mint '{"email":"retired@old-radios.example","aff":{"id":"org-old-radios"}}')"
hx_call "$T"; hx_expect d2 403 "a known but INACTIVE vendor org is refused the same way"

hx_step "(e) stale snapshot -> 403 even for an active vendor"
hx_snapshot "$SNAP" 172800
hx_say "org-snapshot.json re-stamped generated_at = 48h ago (max age 24h)"
T="$(hx_mint '{"email":"late.arrival@bluefield-sensors.example","aff":{"id":"org-bluefield-sensors"}}')"
hx_call "$T"; hx_expect e 403 "auto-roster switches itself off on a stale snapshot; the owner refreshes it"
hx_snapshot "$SNAP" 0

hx_step "(f) wrong audience -> 401"
T="$(hx_mint '{"email":"vendor.one@acme-drones.example","aud":"oauth2-proxy-some-other-service"}')"
hx_call "$T"; hx_expect f 401 "a token minted for another client is not for this service"

hx_step "(g) issuer without the trailing slash -> 401"
T="$(hx_mint "{\"email\":\"vendor.one@acme-drones.example\",\"iss\":\"${HX_ISSUER%/}\"}")"
hx_call "$T"; hx_expect g 401 "iss is compared as an exact string; ${HX_ISSUER%/} is not $HX_ISSUER"

hx_step "(h) aff.id disagrees with the roster row -> 200 plus an org_mismatch audit line"
T="$(hx_mint '{"email":"vendor.one@acme-drones.example","aff":{"id":"org-bluefield-sensors"}}')"
hx_call "$T"; hx_expect h 200 "the roster decides (org-acme-drones); the token's org is logged as evidence"
hx_assert "an org_mismatch audit line was written" hx_audit org_mismatch; hx_audit_show org_mismatch

hx_step "(i) expired token -> 401"
T="$(hx_mint '{"email":"vendor.one@acme-drones.example","exp_seconds":-30}')"
hx_call "$T"; hx_expect i 401 "exp is checked; under a live session this is the token_lifespan pin"

hx_step "Stop both processes"
hx_stop_all; hx_ok "issuer and service stopped (trap also covers Ctrl-C)"
hx_say "logs: $HX_RUN/issuer.log  $HX_RUN/service.log"
echo
hx_say "Next: bash scenarios/03-withdraw/run.sh"
hx_summary
