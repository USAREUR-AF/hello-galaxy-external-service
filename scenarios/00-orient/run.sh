#!/usr/bin/env bash
# Scenario 00 — Orient: what an external service is, and the boundary rule.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/hello-external.sh"

hx_banner "Orient — a service the goatnet does not run borrows its sign-in" \
          "One declaration in, one declaration out, no footprint left behind."

hx_step "The setting"
hx_say "A goatnet runs an identity plane: people sign in once at the site's Ory Hydra"
hx_say "and get an id_token that names them (sub, email, groups, and on some goatnets"
hx_say "aff.id, their organisation). Core services on the management host use it."
hx_say "An EXTERNAL service is one the goatnet does not build or deploy: it runs on its own"
hx_say "host, is not core, and is often temporary — an event registry, a demo."
hx_say "It still wants goatnet sign-in, a name on the goatnet's edge, and a status row."

hx_step "The three things this repo shows"
hx_note "declare:   one YAML file is the service's whole goatnet-side footprint  (scenario 01)"
hx_note "verify:    the service checks the goatnet's tokens itself and authorizes"
hx_note "           from its own roster; claims grant nothing on their own  (scenario 02)"
hx_note "withdraw:  the same file, marked enabled: false, and a check refuses any"
hx_note "           stray reference to the service's name elsewhere  (scenario 03)"

hx_step "The trust rule"
hx_say "The provider authenticates. The service authorizes. A token's claims are"
hx_say "evidence, never a grant: the service decides from its own records."

hx_step "Why the fence lives on the service's host"
hx_say "The host joins the mesh in the EXTERNAL-INFRA tier, which every role group"
hx_say "reaches directly. A fence on the management host in front of it would be a"
hx_say "fence with a gap beside it. So the service (or an oauth2-proxy beside it)"
hx_say "verifies signature, issuer, audience and expiry on every request, and binds"
hx_say "its mesh IP, never 0.0.0.0."

hx_step "The boundary rule"
hx_say "A temporary service's name may appear in the goatnet's configuration ONLY in"
hx_say "its own declaration file. A CI check fails any change that names it anywhere"
hx_say "else. That is what makes withdrawal complete rather than hopeful."

hx_step "Prerequisites"
if hx_preflight; then hx_ok "python3 + curl + PyJWT/cryptography/PyYAML present"; else hx_fail "see above"; fi
hx_honest "the issuer used by scenario 02 is SIMULATED (local-issuer/); the apply step,"
hx_honest "the edge and the checks run on the goatnet — docs/honesty-matrix.md grades each piece."

hx_step "What's next"
hx_note "01-declare                 validate the declaration; see what it derives; see refusals"
hx_note "02-sign-in-and-authorize   start the issuer + service, walk every rule with real tokens"
hx_note "03-withdraw                mark it withdrawn; see what is removed; run the footprint check"
echo
hx_say "Run them in order: bash scenarios/01-declare/run.sh"
