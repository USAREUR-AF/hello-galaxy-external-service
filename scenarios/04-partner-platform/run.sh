#!/usr/bin/env bash
# Scenario 04 — a platform with several endpoints, and who terminates TLS.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/hello-external.sh"
hx_preflight || exit 1

DECL="examples/northwind-platform.zagros.yml"
SITE=(--site-id zagros --site-dns-zone netbird.zagros.example --mesh-ip-a 100.127.0.1)

hx_banner "A platform is not one service on one name" \
          "Fourteen surfaces, one declaration, one label of their own."

hx_step "The declaration"
hx_cmd "cat examples/northwind-platform.zagros.yml"
grep -v '^#' "$DECL" | sed '/^---$/d' | hx_quote

hx_step "What the goatnet derives when YOU terminate TLS (tls: partner)"
hx_cmd "tools/validate-declaration.py examples/northwind-platform.zagros.yml --site-id zagros"
val "$DECL" "${SITE[@]}" | hx_quote
hx_assert "the partner-mode declaration is accepted for state=present" val "$DECL" "${SITE[@]}" --quiet
hx_honest "the goatnet publishes NO route, NO backend and NO certificate for these names."
hx_honest "Its mesh-only allowlist is not the gate either: reachability control is yours."
delegates() { val "$DECL" "${SITE[@]}" | grep -qF '_acme-challenge.northwind.zagros.netbird.zagros.example  CNAME  northwind.acme.example.com'; }
no_public_address() { ! val "$DECL" "${SITE[@]}" | sed -n '/PUBLIC DNS/,/your certificate/p' | grep -qE ' A |100\.64\.'; }
hx_assert "the only public record is the certificate-validation CNAME into the owner's zone" delegates
hx_assert "no address is published in public DNS" no_public_address
hx_honest "a trusted certificate without serving anything publicly: Let's Encrypt's DNS-01"
hx_honest "challenge is answered in a zone YOU control, through that one delegation record."

hx_step "The same declaration with the goatnet's edge in front (tls: edge)"
EDGE="$HX_RUN/decl-edge.yml"
"$HX_PY" - "$DECL" "$EDGE" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
b = d["external_service_northwind"]
b.pop("tls", None); b.pop("mesh_ip", None); b.pop("acme_delegate", None); b.pop("mesh_peer", None)
b["backend_url"] = "http://100.127.0.76:8443"
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
hx_cmd "tools/validate-declaration.py <same file, tls dropped, backend added>"
val "$EDGE" "${SITE[@]}" | hx_quote
hx_assert "the edge-mode declaration is accepted too" val "$EDGE" "${SITE[@]}" --quiet
hx_say "One router now carries every name, and every name joins the mesh-only certificate."

hx_step "partner mode without mesh_ip is refused"
BAD1="$HX_RUN/decl-no-mesh-ip.yml"
"$HX_PY" - "$DECL" "$BAD1" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["external_service_northwind"].pop("mesh_ip")
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
hx_cmd "tools/validate-declaration.py <partner mode, mesh_ip removed>"
val "$BAD1" "${SITE[@]}" 2>&1 | tail -3 | hx_quote
hx_assert "partner mode with nowhere to point the names is refused" hx_not val "$BAD1" "${SITE[@]}" --quiet

hx_step "partner mode needs a certificate-validation zone of its own"
mutate() { # $1 file-suffix, $2 python statements on b, $3 description
  local f="$HX_RUN/decl-$1.yml"
  "$HX_PY" - "$DECL" "$f" "$2" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
b = d["external_service_northwind"]
exec(sys.argv[3])
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
  if [ ! -s "$f" ]; then HX_FAIL=$((HX_FAIL+1)); hx_fail "$3 (test fixture was not written)"; return; fi
  hx_assert "$3" hx_not val "$f" "${SITE[@]}" --quiet
}
mutate no-delegate   'b.pop("acme_delegate")'                                   "partner mode without acme_delegate is refused -- no way to a trusted certificate"
mutate own-zone      'b["acme_delegate"] = "acme.zagros.netbird.zagros.example"' "an acme_delegate inside the goatnet's own zone is refused -- it delegates nothing"
mutate edge-delegate 'b.pop("tls"); b.pop("mesh_ip"); b["backend_url"] = "http://100.127.0.76:8443"' "edge mode with an acme_delegate is refused -- the goatnet holds that certificate"
mutate bad-peer      'b["mesh_peer"] = "no spaces allowed"'                     "a malformed mesh_peer is refused"

hx_step "an unknown tls value is refused"
BAD2="$HX_RUN/decl-bad-tls.yml"
"$HX_PY" - "$DECL" "$BAD2" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["external_service_northwind"]["tls"] = "passthrough"
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
hx_cmd "tools/validate-declaration.py <tls: passthrough>"
val "$BAD2" "${SITE[@]}" 2>&1 | tail -3 | hx_quote
hx_assert "tls is a closed set: edge or partner" hx_not val "$BAD2" "${SITE[@]}" --quiet

hx_step "Only this service's own names, and only one level of nesting"
refuse() { # $1 file-suffix, $2 hostnames as a python list, $3 description
  local f="$HX_RUN/decl-$1.yml"
  "$HX_PY" - "$DECL" "$f" "$2" <<'PY'
import sys, yaml, ast
d = yaml.safe_load(open(sys.argv[1]))
d["external_service_northwind"]["hostnames"] = ast.literal_eval(sys.argv[3])
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
  # A refusal only counts if the declaration it refused exists.
  if [ ! -s "$f" ]; then HX_FAIL=$((HX_FAIL+1)); hx_fail "$3 (test fixture was not written)"; return; fi
  hx_assert "$3" hx_not val "$f" "${SITE[@]}" --quiet
}
hx_say "Each is refused by the same rule the goatnet applies before anything is published:"
refuse bare-label   "['northwind', 'api']"                 "a bare generic label (api) is refused -- it would take a goatnet-wide name"
refuse two-levels   "['northwind', 'demo.console.northwind']"  "nesting two levels (demo.console.northwind) is refused -- write demo-console.northwind"
refuse other-parent "['northwind', 'api.otherco']"         "nesting under another service's name (api.otherco) is refused"
refuse other-prefix "['northwind', 'otherco-api']"         "another service's prefix (otherco-api) is refused"
refuse malformed    "['northwind', 'API..northwind']"          "an uppercase or empty label (API..northwind) is refused"
refuse long-label   "['northwind', 'northwind-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx']" "a label over 63 characters is refused"

hx_step "What the certificate carries"
FLAT="$HX_RUN/decl-flat.yml"
"$HX_PY" - "$DECL" "$FLAT" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
b = d["external_service_northwind"]
b.pop("tls", None); b.pop("mesh_ip", None); b.pop("acme_delegate", None); b.pop("mesh_peer", None)
b["backend_url"] = "http://100.127.0.76:8443"
b["hostnames"] = ["northwind", "northwind-api", "northwind-audit"]
# per-hostname status overrides are keyed by the entries just replaced
(b.get("status") or {}).pop("hostnames", None)
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
hx_cmd "tools/validate-declaration.py <edge, flat: northwind, northwind-api, northwind-audit>"
val "$FLAT" "${SITE[@]}" | grep -A1 "certificate:" | hx_quote
hx_cmd "tools/validate-declaration.py <edge, nested: northwind, api.northwind, ...>"
val "$EDGE" "${SITE[@]}" | grep -A1 "certificate:" | hx_quote
val "$FLAT" "${SITE[@]}" > "$HX_RUN/flat.out"; val "$EDGE" "${SITE[@]}" > "$HX_RUN/nested.out"
flat_adds_nothing() { grep -qF 'certificate:  *.zagros.' "$HX_RUN/flat.out" && ! grep -qF '*.northwind.' "$HX_RUN/flat.out"; }
nested_adds_one()   { [ "$(grep -cF '*.northwind.zagros.' "$HX_RUN/nested.out")" = 1 ]; }
hx_assert "flat names add nothing to the certificate beyond the site wildcard" flat_adds_nothing
hx_assert "a nesting service adds exactly one certificate name of its own" nested_adds_one
hx_honest "the certificate grows with services that NEST, not with services or hostnames:"
hx_honest "a thousand flat services add nothing; each nesting service adds one name."
hx_honest "DNS still has no wildcard -- every name is a record the goatnet writes out."

hx_summary
