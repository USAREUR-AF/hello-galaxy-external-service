# shellcheck shell=bash
# hello-external.sh — shared library for the hello-galaxy-external-service scenarios.
#
# Sourced by every scenario driver. Provides path resolution, narration, colour,
# lightweight assertions, and the helpers that start and stop the two local
# processes (the simulated issuer and the hello service). Same shape as
# lib/access-mgmt.sh in hello-galaxy-access-mgmt.
#
# Everything here runs on the laptop. Nothing talks to a goatnet. The
# honesty grading of each piece is in docs/honesty-matrix.md.

set -o pipefail

HX_LIB="${BASH_SOURCE[0]}"
HX_ROOT="$(cd "$(dirname "$HX_LIB")/.." && pwd)"
export HX_ROOT
# Every scenario runs from the repo root so printed paths are short and portable.
cd "$HX_ROOT" || exit 2
HX_RUN="${HX_RUN:-.run}"
export HX_RUN
mkdir -p "$HX_RUN"

# Fixed local ports. Override with HX_ISSUER_PORT / HX_SERVICE_PORT.
HX_ISSUER_PORT="${HX_ISSUER_PORT:-9401}"
HX_SERVICE_PORT="${HX_SERVICE_PORT:-9402}"
# The issuer's base URL WITH the trailing slash. The slash is load-bearing:
# the `iss` claim is this exact string and the service compares it exactly.
HX_ISSUER="http://127.0.0.1:${HX_ISSUER_PORT}/"
HX_SERVICE="http://127.0.0.1:${HX_SERVICE_PORT}"
# The OAuth2 client id the declaration registers and the service expects as `aud`.
HX_CLIENT_ID="${HX_CLIENT_ID:-oauth2-proxy-hello-external}"
export HX_ISSUER HX_SERVICE HX_CLIENT_ID

# The python that has the dependencies. Set HX_PY to force one; otherwise the
# first of python3, python that can import all three. Windows needs this: the
# `python3` on PATH there is usually the Microsoft Store stub, which carries no
# packages while `pip` installs into a different interpreter — so the honest
# report is "this interpreter has them", not "the modules are missing".
# Exported because tools/footprint-guard-demo.sh runs as its own process.
hx_pick_python() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || continue
    "$c" -c 'import jwt, cryptography, yaml' 2>/dev/null && { printf '%s
' "$c"; return 0; }
  done
  # None is complete. Return the first that exists so the preflight reports a
  # missing-module error against a real interpreter instead of a missing one.
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 && { printf '%s
' "$c"; return 0; }
  done
  return 1
}
HX_PY="${HX_PY:-$(hx_pick_python python3 python || echo python3)}"
export HX_PY

# --- presentation -----------------------------------------------------------
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_BLUE=""
fi

HX_STEP=0
hx_step()  { HX_STEP=$((HX_STEP+1)); printf '\n%s%s── Step %d ─ %s%s\n' "$C_BOLD" "$C_CYAN" "$HX_STEP" "$1" "$C_RESET"; }
hx_say()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
hx_note()  { printf '%s  • %s%s\n' "$C_BLUE" "$*" "$C_RESET"; }
hx_cmd()   { printf '%s$ %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
hx_ok()    { printf '%s  ✓ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
hx_warn()  { printf '%s  ! %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
hx_fail()  { printf '%s  ✗ %s%s\n' "$C_RED" "$*" "$C_RESET"; }
hx_honest(){ printf '%s  ⓘ honesty: %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
hx_quote() { sed 's/^/    │ /'; }
hx_banner() {
  printf '\n%s%s════════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '%s%s  %s%s\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"
  printf '%s%s════════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  [ -n "${2:-}" ] && printf '%s  %s%s\n' "$C_DIM" "$2" "$C_RESET"
  printf '%s  mode: laptop-local (simulated issuer, real service code)%s\n' "$C_DIM" "$C_RESET"
}

# --- assertions -------------------------------------------------------------
HX_PASS=0; HX_FAIL=0
hx_assert() { local d="$1"; shift; if "$@"; then HX_PASS=$((HX_PASS+1)); hx_ok "$d"; return 0; else HX_FAIL=$((HX_FAIL+1)); hx_fail "$d"; return 1; fi; }
hx_summary() {
  printf '\n%s%s── result ─ %d passed, %d failed%s\n' \
    "$C_BOLD" "$( [ "$HX_FAIL" -eq 0 ] && echo "$C_GREEN" || echo "$C_RED")" \
    "$HX_PASS" "$HX_FAIL" "$C_RESET"
  [ "$HX_FAIL" -eq 0 ]
}

# hx_not <cmd...> -> 0 iff the command fails (for asserting a refusal), output hidden.
hx_not() { ! "$@" >/dev/null 2>&1; }
# hx_quiet <cmd...> -> the command's exit status, output hidden.
hx_quiet() { "$@" >/dev/null 2>&1; }
# val <args...> -> the declaration validator.
val() { "$HX_PY" tools/validate-declaration.py "$@"; }

# --- preflight --------------------------------------------------------------
hx_preflight() {
  local rc=0
  command -v "$HX_PY" >/dev/null 2>&1 || { hx_fail "no python on PATH (tried python3, python)"; rc=1; }
  command -v curl >/dev/null 2>&1 || { hx_fail "curl not on PATH"; rc=1; }
  if [ "$rc" -eq 0 ] && ! "$HX_PY" -c 'import jwt, cryptography, yaml' 2>/dev/null; then
    hx_fail "$HX_PY is missing modules — run:  $HX_PY -m pip install -r requirements.txt"; rc=1
  fi
  return "$rc"
}

# --- the two local processes ------------------------------------------------
HX_ISSUER_PID=""; HX_SERVICE_PID=""

hx_wait_http() { # url, seconds
  local url="$1" n="${2:-15}" i=0
  while [ "$i" -lt "$((n*4))" ]; do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then return 0; fi
    sleep 0.25; i=$((i+1))
  done
  return 1
}

hx_start_issuer() {
  "$HX_PY" local-issuer/issuer.py --port "$HX_ISSUER_PORT" >"$HX_RUN/issuer.log" 2>&1 &
  HX_ISSUER_PID=$!
  hx_wait_http "${HX_ISSUER}.well-known/openid-configuration" 15 \
    || { hx_fail "issuer did not come up; see $HX_RUN/issuer.log"; return 1; }
  hx_ok "simulated issuer up at $HX_ISSUER (pid $HX_ISSUER_PID)"
}

# hx_start_service <roster-file> <snapshot-file> [extra env assignments...]
hx_start_service() {
  local roster="$1" snapshot="$2"; shift 2
  env HELLO_BIND=127.0.0.1 HELLO_PORT="$HX_SERVICE_PORT" \
      HELLO_ISSUER="$HX_ISSUER" \
      HELLO_JWKS_URL="${HX_ISSUER}.well-known/jwks.json" \
      HELLO_CLIENT_ID="$HX_CLIENT_ID" \
      HELLO_ROSTER_FILE="$roster" \
      HELLO_ORG_SNAPSHOT_FILE="$snapshot" \
      HELLO_AUTO_ROSTER_VENDORS="${HELLO_AUTO_ROSTER_VENDORS:-true}" \
      HELLO_SNAPSHOT_MAX_AGE_SECONDS="${HELLO_SNAPSHOT_MAX_AGE_SECONDS:-86400}" \
      "$@" \
      "$HX_PY" service/hello_service.py >"$HX_RUN/service.log" 2>&1 &
  HX_SERVICE_PID=$!
  hx_wait_http "$HX_SERVICE/healthz" 15 \
    || { hx_fail "service did not come up; see $HX_RUN/service.log"; return 1; }
  hx_ok "hello service up at $HX_SERVICE (pid $HX_SERVICE_PID)"
}

hx_stop_all() {
  local p
  for p in "$HX_SERVICE_PID" "$HX_ISSUER_PID"; do
    [ -n "$p" ] && kill "$p" 2>/dev/null
  done
  wait 2>/dev/null
  HX_ISSUER_PID=""; HX_SERVICE_PID=""
}
trap 'hx_stop_all' EXIT INT TERM

# --- tokens and calls -------------------------------------------------------
# hx_mint '<json claims request>' -> prints the id_token. The request shape is
# the issuer's /mint contract (local-issuer/issuer.py): email, email_verified,
# aff, groups, aud, exp_seconds, iss (override, demo only).
hx_mint() {
  curl -fsS -X POST "${HX_ISSUER}mint" -H 'Content-Type: application/json' -d "$1" \
    | "$HX_PY" -c 'import json,sys; print(json.load(sys.stdin)["id_token"])'
}

# hx_call <token> [path] -> sets HX_STATUS and HX_BODY, prints request + reply.
HX_STATUS=""; HX_BODY=""
hx_call() {
  local tok="$1" path="${2:-/api/me}" out
  out="$(curl -sS -o "$HX_RUN/body.json" -w '%{http_code}' \
          -H "Authorization: Bearer $tok" "$HX_SERVICE$path")"
  HX_STATUS="$out"
  HX_BODY="$("$HX_PY" -c 'import json,sys; print(json.dumps(json.load(sys.stdin), separators=(", ", ": ")))' <"$HX_RUN/body.json" 2>/dev/null || cat "$HX_RUN/body.json")"
  printf '%s  → GET %s  Authorization: Bearer %s…%s\n' "$C_DIM" "$path" "${tok:0:20}" "$C_RESET"
  printf '%s  ← %s  %s%s\n' "$C_DIM" "$HX_STATUS" "$HX_BODY" "$C_RESET"
}

# hx_expect <label> <expected-status> <description>  (uses HX_STATUS)
hx_expect() {
  local label="$1" want="$2" d="$3"
  if [ "$HX_STATUS" = "$want" ]; then
    HX_PASS=$((HX_PASS+1)); printf '%s  ✓ (%s) %s as expected — %s%s\n' "$C_GREEN" "$label" "$want" "$d" "$C_RESET"
  else
    HX_FAIL=$((HX_FAIL+1)); printf '%s  ✗ (%s) expected %s, got %s — %s%s\n' "$C_RED" "$label" "$want" "$HX_STATUS" "$d" "$C_RESET"
  fi
}

# hx_audit <event> -> 0 iff the service log carries that audit event.
hx_audit() { grep -q "audit event=$1" "$HX_RUN/service.log" 2>/dev/null; }
hx_audit_show() { grep "audit event=$1" "$HX_RUN/service.log" 2>/dev/null | tail -1 | hx_quote; }

# hx_snapshot <out-file> <age-seconds> -> writes the org snapshot stamped
# generated_at = now - age. The org list comes from service/org-snapshot.json.
hx_snapshot() {
  "$HX_PY" - service/org-snapshot.json "$1" "$2" <<'PY'
import datetime, json, sys
src, out, age = sys.argv[1], sys.argv[2], int(sys.argv[3])
doc = json.load(open(src))
stamp = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=age)
doc["generated_at"] = stamp.strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump(doc, open(out, "w"), indent=2)
PY
}
