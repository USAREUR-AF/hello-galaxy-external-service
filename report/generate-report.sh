#!/usr/bin/env bash
# generate-report.sh — run every scenario, capture the real output, and write a
# self-contained HTML report (report/report.html) with the arc, the per-step
# status codes read back from the scenario 02 capture, and the honesty matrix.
# Nothing in the report is typed in by hand: re-run it and every line is fresh.
#
# usage:  report/generate-report.sh            # SKIP_RUN=1 reuses existing captures
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CAP="$HERE/.captures"; mkdir -p "$CAP"
OUT="$HERE/report.html"
cd "$ROOT" || exit 2

STAMP="$(date -u '+%Y-%m-%d %H:%M:%SZ')"
SCENS=(00-orient 01-declare 02-sign-in-and-authorize 03-withdraw 04-partner-platform)
if [ "${SKIP_RUN:-0}" = "1" ] && [ -f "$CAP/04-partner-platform.txt" ]; then
  echo "==> SKIP_RUN=1 — reusing existing captures"
else
  echo "==> running scenarios (capturing real output)…"
  for s in "${SCENS[@]}"; do
    echo "    - $s"
    NO_COLOR=1 bash "scenarios/$s/run.sh" >"$CAP/$s.txt" 2>&1
    echo $? >"$CAP/$s.rc"
  done
fi

passes() { local tot=0 s n; for s in "${SCENS[@]}"; do
    n="$(sed -n 's/.*result ─ \([0-9]*\) passed.*/\1/p' "$CAP/$s.txt" | head -1)"; tot=$((tot + ${n:-0}))
  done; echo "$tot"; }
fails() { local tot=0 s n; for s in "${SCENS[@]}"; do
    n="$(sed -n 's/.*result ─ [0-9]* passed, \([0-9]*\) failed.*/\1/p' "$CAP/$s.txt" | head -1)"; tot=$((tot + ${n:-0}))
  done; echo "$tot"; }
scen_result() { sed -n 's/.*\(result ─ [0-9]* passed, [0-9]* failed\).*/\1/p' "$CAP/$1.txt" | head -1; }
TOTAL_PASS="$(passes)"; TOTAL_FAIL="$(fails)"

esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
cap_html() { esc < "$CAP/$1.txt"; }

# The per-step rows of scenario 02, read back from its capture:
#   "  ✓ (a) 200 as expected — ..."  or  "  ✗ (a) expected 200, got 500 — ..."
step_rows() {
  grep -E '^  [✓✗] \([a-z0-9]+\) ' "$CAP/02-sign-in-and-authorize.txt" | while IFS= read -r line; do
    local mark label status why
    mark="${line:2:1}"
    label="$(printf '%s' "$line" | sed -n 's/^  [✓✗] (\([a-z0-9]*\)).*/\1/p')"
    if [ "$mark" = "✓" ]; then
      status="$(printf '%s' "$line" | sed -n 's/^  ✓ ([a-z0-9]*) \([0-9]*\) as expected.*/\1/p')"
    else
      status="$(printf '%s' "$line" | sed -n 's/^  ✗ ([a-z0-9]*) expected [0-9]*, got \([0-9]*\).*/\1/p')"
    fi
    why="$(printf '%s' "$line" | sed 's/^[^—]*— //' | esc)"
    printf '<tr><td class="mono">(%s)</td><td class="mono %s">%s</td><td>%s</td><td>%s</td></tr>\n' \
      "$label" "$( [ "$mark" = "✓" ] && echo ok || echo bad )" "$status" \
      "$( [ "$mark" = "✓" ] && echo '<span class="tick">as expected</span>' || echo '<span class="cross">NOT as expected</span>' )" "$why"
  done
}
AUDIT_AUTO="$(grep -m1 'audit event=auto_rostered' "$CAP/02-sign-in-and-authorize.txt" | sed 's/^ *│ *//' | esc)"
AUDIT_MISMATCH="$(grep -m1 'audit event=org_mismatch' "$CAP/02-sign-in-and-authorize.txt" | sed 's/^ *│ *//' | esc)"
GUARD_FAIL="$(grep -m1 "FAIL: external service 'hello-external'" "$CAP/03-withdraw.txt" | sed 's/^ *│ *//' | esc)"
GUARD_OK="$(grep -m1 "OK: external service 'hello-external'" "$CAP/03-withdraw.txt" | sed 's/^ *│ *//' | esc)"

echo "==> writing $OUT"
{
cat <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>hello-galaxy-external-service — the external service golden path, run</title>
<style>
:root{--bg:#0e1116;--panel:#161b22;--panel2:#1c232c;--ink:#f0f4f8;--dim:#b3bec9;--line:#2a323c;
  --accent:#f5b14c;--green:#4cd964;--red:#ff6b6b;--blue:#79b8ff;
  --mono:"SFMono-Regular",ui-monospace,Menlo,Consolas,monospace}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 ui-sans-serif,-apple-system,Segoe UI,Roboto,Helvetica,Arial}
.wrap{max-width:980px;margin:0 auto;padding:40px 24px 80px}
header{padding:20px 0 12px;border-bottom:1px solid var(--line);margin-bottom:28px}
.kick{color:var(--accent);font:600 13px/1.4 var(--mono);letter-spacing:.12em;text-transform:uppercase}
h1{font-size:30px;margin:.3em 0 .2em}
h2{font-size:22px;margin:2.2em 0 .5em;padding-top:.4em;border-top:1px solid var(--line)}
.lede{color:var(--dim);font-size:17px;max-width:72ch}
.meta{color:var(--dim);font:13px/1.5 var(--mono);margin-top:12px}
.badge{display:inline-block;padding:3px 10px;border-radius:999px;font:600 12px var(--mono);border:1px solid var(--line);background:var(--panel)}
.badge.ok{color:var(--green);border-color:#1f6f3f}.badge.bad{color:var(--red);border-color:#7f2a2a}
.grid{display:grid;gap:14px;grid-template-columns:repeat(4,1fr);margin:20px 0}
.card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:16px}
.card .n{font:700 24px var(--mono)}.card .l{color:var(--dim);font-size:12.5px;margin-top:3px}
table{width:100%;border-collapse:collapse;margin:14px 0;font-size:14.5px}
th,td{text-align:left;padding:9px 12px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--dim);font:600 12px/1.4 var(--mono);text-transform:uppercase;letter-spacing:.06em}
td.mono,code{font-family:var(--mono)}code{background:var(--panel2);padding:1px 6px;border-radius:6px;font-size:13px}
td.ok{color:var(--green);font-weight:700}td.bad{color:var(--red);font-weight:700}
.tick{color:var(--green);font-weight:700}.cross{color:var(--red);font-weight:700}
.term{background:#0a0d12;border:1px solid var(--line);border-radius:10px;padding:14px 16px;overflow:auto}
.term pre{margin:0;font:13px/1.5 var(--mono);color:#d6dee6;white-space:pre-wrap;word-break:break-word}
details{background:var(--panel);border:1px solid var(--line);border-radius:10px;margin:12px 0;padding:4px 16px}
summary{cursor:pointer;font-weight:600;padding:10px 0}
.pill{font:600 11px var(--mono);padding:2px 8px;border-radius:999px;white-space:nowrap}
.pill.real{color:var(--green);background:#10261a;border:1px solid #1f6f3f}
.pill.else{color:var(--blue);background:#0f1f33;border:1px solid #2a4f7f}
.pill.sim{color:var(--accent);background:#241c0e;border:1px solid #6f561f}
.note{color:var(--dim);font-size:14px;border-left:3px solid var(--accent);padding:6px 0 6px 14px;margin:14px 0}
a{color:var(--blue)}
@media(max-width:720px){.grid{grid-template-columns:repeat(2,1fr)}}
</style></head><body><div class="wrap">

<header>
  <div class="kick">hello-galaxy · usareur-af</div>
  <h1>The external service golden path, run</h1>
  <p class="lede">A service the goatnet does not run borrows its sign-in from one declaration file,
  verifies the tokens itself, authorizes from its own roster, and is withdrawn the same way with
  nothing left behind. Everything below was captured from a laptop run with a simulated
  issuer and the real service code.</p>
  <div class="meta">generated $STAMP · <span class="badge $([ "$TOTAL_FAIL" -eq 0 ] && echo ok || echo bad)">$TOTAL_PASS checks passed, $TOTAL_FAIL failed</span></div>
</header>

<div class="grid">
  <div class="card"><div class="n">1</div><div class="l">declaration file per service per goatnet</div></div>
  <div class="card"><div class="n">$(grep -c -E '^  [✓✗] \([a-z0-9]+\) ' "$CAP/02-sign-in-and-authorize.txt")</div><div class="l">relying-party rules exercised with real tokens</div></div>
  <div class="card"><div class="n">$(grep -c '✗' "$CAP/01-declare.txt" "$CAP/03-withdraw.txt" "$CAP/02-sign-in-and-authorize.txt" | awk -F: '{s+=$2} END{print s+0}')</div><div class="l">assertions that did not hold</div></div>
  <div class="card"><div class="n">0</div><div class="l">other files the service may be named in</div></div>
</div>

<h2>1. Declare</h2>
<p>One YAML file, <code>examples/hello-external.zagros.yml</code>, is the whole goatnet-side footprint.
<code>tools/validate-declaration.py</code> applies the goatnet's own rules and previews what it
derives: the hostname, the issuer with its trailing slash, the JWKS URL, the OAuth2 client, the edge
route and certificate name, the DNS record and the status row. Three refusals follow: a LAN backend, a door
outside the closed set, a passed <code>retire_after</code>.</p>
<p>Scenario result: <code>$(scen_result 01-declare)</code></p>
<details><summary>Full captured output — 01-declare</summary><div class="term"><pre>$(cap_html 01-declare)</pre></div></details>

<h2>2. Sign in and authorize</h2>
<p>The provider authenticates, the service authorizes. A simulated issuer signs RS256 tokens; the real
service code decides on each one. Every refusal names who can fix it.</p>
<table>
<tr><th>Step</th><th>Status</th><th>Held?</th><th>What it shows</th></tr>
$(step_rows)
</table>
<p>Audit lines the service wrote (read back from the capture):</p>
<div class="term"><pre>${AUDIT_AUTO:-—}
${AUDIT_MISMATCH:-—}</pre></div>
<p>Scenario result: <code>$(scen_result 02-sign-in-and-authorize)</code></p>
<details><summary>Full captured output — 02-sign-in-and-authorize</summary><div class="term"><pre>$(cap_html 02-sign-in-and-authorize)</pre></div></details>

<h2>3. Withdraw</h2>
<p>Withdrawal is refused while the declaration is enabled; it is the owner's edit, not the platform
team's flag. Once <code>enabled: false</code>, the goatnet deletes the OAuth2 client and drops the route,
the certificate name, the DNS record and the status row. The footprint check is what makes that complete:
it fails any change that names a temporary service outside its own declaration.</p>
<div class="term"><pre>${GUARD_FAIL:-—}
${GUARD_OK:-—}</pre></div>
<p>Scenario result: <code>$(scen_result 03-withdraw)</code></p>
<details><summary>Full captured output — 03-withdraw</summary><div class="term"><pre>$(cap_html 03-withdraw)</pre></div></details>

<h2>4. A platform with several endpoints</h2>
<p>One declaration can carry several endpoint names through <code>hostnames:</code>, and <code>tls:</code>
decides who terminates. In <code>edge</code> mode the goatnet publishes one route carrying every name and
puts every name on its own certificate. In <code>partner</code> mode it publishes DNS records pointing at
the owner's host and nothing else at all &mdash; no route, no backend, no certificate &mdash; so reachability
control moves to that host. Every hostname is one DNS label; the mesh zone does not nest.</p>
<p>Scenario result: <code>$(scen_result 04-partner-platform)</code></p>
<details><summary>Full captured output — 04-partner-platform</summary><div class="term"><pre>$(cap_html 04-partner-platform)</pre></div></details>

<h2>Orientation</h2>
<details><summary>Full captured output — 00-orient</summary><div class="term"><pre>$(cap_html 00-orient)</pre></div></details>

<h2>Honesty matrix</h2>
<p class="note">Three grades. REAL runs here. REAL-BUT-ELSEWHERE runs on the goatnet. SIMULATED is a stand-in and says what it does not do.</p>
<table>
<tr><th>Element</th><th>Grade</th><th>Where, and what is true</th></tr>
<tr><td>The relying party: signature, iss, aud, exp, email, email_verified, roster, vendor auto-roster, snapshot age, org_mismatch audit</td><td><span class="pill real">REAL</span></td><td>service/hello_service.py; scenario 02 asserts every status code</td></tr>
<tr><td>/healthz open; /api/me returns the principal</td><td><span class="pill real">REAL</span></td><td>scenario 02</td></tr>
<tr><td>Roster and org snapshot</td><td><span class="pill real">REAL files</span></td><td>illustrative content; not exported from a goat registry</td></tr>
<tr><td>Declaration validation</td><td><span class="pill real">REAL, copied</span></td><td>the same rules the goatnet applies before anything is changed</td></tr>
<tr><td>The derived preview</td><td><span class="pill else">REAL-BUT-ELSEWHERE</span></td><td>the goatnet renders the route, the certificate, the DNS records and the status rows; this repo prints their shapes</td></tr>
<tr><td>The footprint check</td><td><span class="pill real">REAL, copied</span></td><td>the goatnet's check reproduced &mdash; same glob shape, file-name rule, tokens and messages &mdash; on a scratch tree</td></tr>
<tr><td>The OIDC issuer</td><td><span class="pill sim">SIMULATED</span></td><td>local-issuer/issuer.py stands in for Ory Hydra: real JWKS and RS256 signatures, no login flow, mints any claims asked for</td></tr>
<tr><td>OAuth2 client register / pin / delete; pre-flight; edge, DNS push, status page</td><td><span class="pill else">REAL-BUT-ELSEWHERE</span></td><td>all of it happens on the goatnet when a declaration is applied; not run here</td></tr>
<tr><td>Machine enrollment of the host</td><td><span class="pill else">REAL-BUT-ELSEWHERE</span></td><td>your custodian enrolls it; described in docs/do-it-for-real.md</td></tr>
<tr><td>The aff.id claim on a goatnet</td><td><span class="pill else">ELSEWHERE, off by default</span></td><td>a per-goatnet switch, off by default; the simulated issuer mints it so the rule can be shown</td></tr>
<tr><td>email_verified on console-minted identities</td><td><span class="pill sim">depends on the goatnet</span></td><td>identities minted without email_verified: true are refused until verified at the identity provider</td></tr>
</table>

<p class="meta">This report is regenerated by <code>report/generate-report.sh</code>.</p>
</div></body></html>
HTML
} > "$OUT"
echo "==> done: $OUT"
