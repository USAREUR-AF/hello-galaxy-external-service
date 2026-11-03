#!/usr/bin/env bash
# Scenario 03 — Withdraw: the same file, marked withdrawn, and the footprint check.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/hello-external.sh"
hx_preflight || exit 1
DECL="examples/hello-external.zagros.yml"
GONE="$HX_RUN/decl-withdrawn.yml"

hx_banner "Withdraw — your edit, then one apply, then nothing remembers it" \
          "Withdrawal is refused while the service is enabled; a check keeps the name out of the goatnet."

hx_step "Withdrawal is refused while the service is still enabled"
hx_cmd "tools/validate-declaration.py examples/hello-external.zagros.yml --state absent"
val "$DECL" --state absent | hx_quote
hx_assert "withdrawal is refused for an enabled declaration" hx_not val "$DECL" --state absent

hx_step "You set enabled: false (on a copy here)"
sed 's/^  enabled: true/  enabled: false/' "$DECL" > "$GONE"
hx_cmd "sed 's/enabled: true/enabled: false/' examples/hello-external.zagros.yml"
grep -n '^  enabled:' "$GONE" | hx_quote
hx_cmd "tools/validate-declaration.py <withdrawn copy> --state absent"
val "$GONE" --state absent | hx_quote
hx_assert "withdrawal is accepted once the declaration says so" hx_quiet val "$GONE" --state absent
hx_assert "the withdrawn declaration can no longer be applied" hx_not val "$GONE" --quiet

hx_step "What the goatnet removes when the service is withdrawn"
cat <<'Q' | hx_quote
Withdrawal is YOUR edit, not the platform team's flag. You set `enabled: false`
in the declaration (or delete the file); they then apply it once more, and every
derived thing disappears because the loops that produced it no longer see the
service. Applying a removal while the declaration is still enabled is refused —
that ordering is what stops a live service being switched off by accident.
Q
hx_say "what goes, in order:"
hx_note "the OAuth2 client at the goatnet's identity provider    deleted"
hx_note "the route and the certificate name on the goatnet's edge  gone"
hx_note "the mesh DNS record for hello.zagros.<zone>                 gone"
hx_note "the status-page row                                       gone"
hx_honest "not run here: removing those needs the goatnet itself. Withdraw before you delete"
hx_honest "the file: a file deleted first leaves its OAuth2 client registered."

hx_step "The footprint check: a temporary service's name may live only in its declaration"
hx_cmd "tools/footprint-guard-demo.sh"
bash tools/footprint-guard-demo.sh | hx_quote
hx_assert "the check failed on a stray reference and passed once it was removed" \
  bash -c "bash tools/footprint-guard-demo.sh >/dev/null 2>&1"

hx_step "After withdrawal"
hx_say "The OAuth2 client, the route, the certificate name, the DNS record and the status row"
hx_say "are gone. Nothing on the goatnet is named for the service, because the check never"
hx_say "let it be. Your own host, roster and audit log are yours to keep or delete."
echo
hx_summary
