#!/usr/bin/env bash
# footprint-guard-demo.sh — show the goatnet's footprint check doing its job,
# on a scratch tree, without a goatnet.
#
# The goatnet's configuration is kept in git, and a CI check there fails any
# change that names a TEMPORARY external service (one whose declaration carries
# `retire_after`) anywhere except its own declaration file. A permanent service
# is reported, never gated. That check is what makes "set enabled: false" a
# complete teardown rather than a hopeful one: if the name cannot be written
# anywhere else, there is nowhere else for a teardown to miss.
#
# The Python below is that check's logic — the declaration glob, the file-name
# rule, the default search tokens, the temporary/permanent split and the
# messages — run over a scratch tree of this script's own making. The directory
# names in that tree are this demo's, not the goatnet's: what is being shown is
# the behaviour, and the behaviour is the same.
#
# What this does:
#   1. builds a scratch git tree with the hello declaration (temporary) and a
#      second, permanent declaration
#   2. plants a stray reference to each name in an unrelated file
#   3. runs the check: FAIL for the temporary one (file:line), NOTE for the
#      permanent one
#   4. removes the stray line and runs the check again: OK
#
# usage: tools/footprint-guard-demo.sh        (exit 0 iff FAIL-then-OK was observed)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
RUNDIR="${HX_RUN:-$ROOT/.run}"; mkdir -p "$RUNDIR"
SCRATCH="$(cd "$RUNDIR" && pwd)/footprint"
GUARD="$SCRATCH/footprint-check.py"

rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/services/zagros" "$SCRATCH/platform/monitoring" "$SCRATCH/.github/workflows" "$SCRATCH/infra"
cd "$SCRATCH" || exit 2
git init -q -b main .
git config user.email "demo@footprint-check.example"; git config user.name "footprint demo"; git config commit.gpgsign false; git config core.autocrlf false

# The hello declaration, under the file name the check requires: the file stem
# and the mapping name must agree.
cp "$ROOT/examples/hello-external.zagros.yml" services/zagros/external-service-hello-external.yml
# A permanent declaration for contrast (no retire_after).
cat > services/zagros/external-service-perma-map.yml <<'YML'
external_service_perma_map:
  name: perma
  backend_url: "http://100.127.0.9:8081"
  door: group-gated
  owner: someone permanent
  enabled: true
YML
# Something innocent.
printf 'name: ci\non: [push]\njobs: {}\n' > .github/workflows/ci.yml
printf '# no services here\n' > infra/main.tf

# ---- the check's logic -------------------------------------------------------
cat > "$GUARD" <<'PY'
# The goatnet's external-service footprint check, reproduced: same declaration
# glob shape, same file-name rule, same default tokens, same messages, and the
# same temporary-fails / permanent-notes split.
import glob, os, re, subprocess, sys
import yaml

SCAN_ROOTS = ["services", "platform", ".github", "infra"]
SELF = "platform/footprint-check.py"
DECL_GLOB = "services/*/external-service-*.yml"

def tracked_files(roots):
    out = subprocess.run(["git", "ls-files", "--", *roots], capture_output=True, text=True, check=True)
    return [p for p in out.stdout.splitlines() if p]

decls = {}
for path in sorted(glob.glob(DECL_GLOB)):
    fname = os.path.basename(path)[len("external-service-"):-len(".yml")]
    with open(path) as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data, dict):
        print(f"FAIL: {path}: not a mapping"); sys.exit(1)
    keys = [k for k in data if k.startswith("external_service_")]
    if len(keys) != 1:
        print(f"FAIL: {path}: must define exactly one external_service_* mapping, found {keys}"); sys.exit(1)
    var = keys[0]
    if var != "external_service_" + fname.replace("-", "_"):
        print(f"FAIL: {path}: variable {var} does not match the file name (expected external_service_{fname.replace('-', '_')})"); sys.exit(1)
    body = data[var] or {}
    if not isinstance(body, dict):
        print(f"FAIL: {path}: {var} must be a mapping"); sys.exit(1)
    decls.setdefault(fname, {"paths": [], "body": body})
    decls[fname]["paths"].append(path.replace(os.sep, "/"))  # git ls-files always says "/"

if not decls:
    print("OK: no external-service declarations")
    sys.exit(0)

files = tracked_files(SCAN_ROOTS)
failed = False
for fname, d in sorted(decls.items()):
    body = d["body"]
    temporary = "retire_after" in body
    tokens = body.get("guard_tokens") or [fname, fname.replace("-", "_"), "external_service_" + fname.replace("-", "_")]
    tokens = [str(t) for t in tokens if str(t).strip()]
    allowed = set(d["paths"]) | {SELF}
    hits = []
    pat = re.compile("|".join(re.escape(t) for t in tokens))
    for f in files:
        if f in allowed:
            continue
        try:
            with open(f, "r", encoding="utf-8", errors="ignore") as fh:
                for n, line in enumerate(fh, 1):
                    if pat.search(line):
                        hits.append(f"{f}:{n}")
        except (OSError, IsADirectoryError):
            continue
    label = "temporary (retire_after %s)" % body["retire_after"] if temporary else "permanent"
    if hits and temporary:
        failed = True
        print(f"FAIL: external service '{fname}' [{label}] is named outside its declaration — a teardown will not visit these:")
        for h in hits:
            print(f"      {h}")
        print(f"      tokens: {tokens}. Move the wiring into the declaration, or drop it; the golden path needs none of it.")
    elif hits:
        print(f"NOTE: external service '{fname}' [{label}] is named in {len(hits)} place(s) outside its declaration (permanent service; not gated)")
    else:
        print(f"OK: external service '{fname}' [{label}] — no footprint outside its declaration")

sys.exit(1 if failed else 0)
PY

PY="${HX_PY:-python3}"
run_check() { git add -A >/dev/null; git -c commit.gpgsign=false commit -q -m "scratch" --allow-empty >/dev/null; (cd "$SCRATCH" && "$PY" "$GUARD"); }

echo "== 1. plant a stray reference to each service in an unrelated file (the kind of wiring a teardown never visits)"
cat > platform/monitoring/exporters.yml <<'YML'
- name: Register an operator key for the hello-external exporter
  debug:
    msg: "wires external_service_hello_external into something else"
- name: And a permanent one, for contrast
  debug:
    msg: "perma-map dashboards"
YML
echo "   platform/monitoring/exporters.yml:1  ... hello-external ..."
echo "   platform/monitoring/exporters.yml:6  ... perma-map ..."
echo
echo "== 2. run the check"
out1="$(run_check)"; rc1=$?
printf '%s\n' "$out1" | sed 's/^/   /'
echo "   exit $rc1"
echo
echo "== 3. remove the stray lines and run the check again"
rm platform/monitoring/exporters.yml
out2="$(run_check)"; rc2=$?
printf '%s\n' "$out2" | sed 's/^/   /'
echo "   exit $rc2"
echo
if [ "$rc1" -eq 1 ] && printf '%s' "$out1" | grep -q "FAIL: external service 'hello-external'" \
   && printf '%s' "$out1" | grep -q "NOTE: external service 'perma-map'" && [ "$rc2" -eq 0 ]; then
  echo "RESULT: the check FAILED on the temporary service's stray reference (file:line named), only NOTED the permanent one, and passed once the reference was gone."
  exit 0
fi
echo "RESULT: unexpected — the check did not behave as the goatnet's does (rc1=$rc1 rc2=$rc2)"
exit 1
