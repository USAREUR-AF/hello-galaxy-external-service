#!/usr/bin/env bash
# Scenario 01 — Declare: validate the declaration and preview what the goatnet derives.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/hello-external.sh"
hx_preflight || exit 1
DECL="examples/hello-external.zagros.yml"

hx_banner "Declare — one file is the whole goatnet-side footprint" \
          "The rules it is checked against, and what the goatnet derives from it."

hx_step "The declaration"
hx_cmd "cat examples/hello-external.zagros.yml"
grep -v '^#' "$DECL" | sed '/^---$/d' | hx_quote

hx_step "Validate it the way the goatnet does, and preview what it derives"
hx_cmd "tools/validate-declaration.py examples/hello-external.zagros.yml --site-id zagros"
val "$DECL" --site-id zagros | hx_quote
hx_assert "the declaration is accepted for state=present" val "$DECL" --quiet
hx_honest "the preview reproduces the shapes of what the goatnet publishes — the lines you"
hx_honest "configure from, the edge route, the DNS record, the status row. It renders none."

hx_step "A LAN backend is refused (the mesh is the outer gate)"
BAD1="$HX_RUN/decl-lan-backend.yml"
sed 's#http://100.127.0.76:9402#http://192.168.1.50:9402#' "$DECL" > "$BAD1"
hx_cmd "sed 's#100.127.0.76#192.168.1.50#' ... | tools/validate-declaration.py"
val "$BAD1" --quiet | hx_quote
hx_assert "backend_url 192.168.1.50 is refused" hx_not val "$BAD1" --quiet

hx_step "A door outside the closed set is refused"
BAD2="$HX_RUN/decl-bad-door.yml"
sed 's#door: authenticated#door: open#' "$DECL" > "$BAD2"
hx_cmd "sed 's#door: authenticated#door: open#' ... | tools/validate-declaration.py"
val "$BAD2" --quiet | hx_quote
hx_assert "door: open is refused (closed set: group-gated, authenticated, in-app, mesh-only)" \
  hx_not val "$BAD2" --quiet

hx_step "A retire_after in the past is refused for present"
BAD3="$HX_RUN/decl-retired.yml"
sed 's#retire_after: "2035-12-31"#retire_after: "2020-01-01"#' "$DECL" > "$BAD3"
hx_cmd "sed 's#retire_after: ...#retire_after: \"2020-01-01\"#' ... | tools/validate-declaration.py"
val "$BAD3" --quiet | hx_quote
hx_assert "a passed retire_after is refused for state=present" hx_not val "$BAD3" --quiet

hx_step "What you do next, on a real goatnet"
hx_note "hand this file to the platform team — it is the whole goatnet-side change"
hx_note "put the client secret in your own deploy environment, under the name you declared"
hx_note "they apply it: one command, and the goatnet publishes the name"
hx_note "configure your service from the lines it prints back — docs/do-it-for-real.md"
echo
hx_say "Next: bash scenarios/02-sign-in-and-authorize/run.sh"
hx_summary
