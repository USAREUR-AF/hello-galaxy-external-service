# Honesty matrix

Every piece of the demo is graded. Three grades:

- **REAL**: the code runs here, in this repo, and the scenario proves it.
- **REAL-BUT-ELSEWHERE**: the thing exists and runs on the goatnet; this repo does not
  contain it. The row says what the goatnet does and what this repo shows instead.
- **SIMULATED**: a stand-in. The row says what it stands in for and what it does not do.

| Element | Grade | Where, and what is true |
|---|---|---|
| The relying party (`service/hello_service.py`): signature, `iss`, `aud`, `exp`, `email`, `email_verified`, roster, vendor auto-roster, snapshot age, `org_mismatch` audit | **REAL** | Scenario 02 runs every rule against real RS256 tokens and asserts the status code |
| `/healthz` open, `/api/me` returns the principal | **REAL** | Scenario 02 |
| The roster and the org snapshot (`service/roster.json`, `service/org-snapshot.json`) | **REAL** files, **illustrative** content | The service reads and rewrites them. The org list is what you would export from the goatnet's registry; it was not exported from one |
| The worked examples (`examples/`) | **REAL** files, **example** content | The shape the goatnet accepts, with documentation addresses. Never proposed to a goatnet |
| Declaration validation (`tools/validate-declaration.py`) | **REAL** logic, copied | The same rules the goatnet applies before anything is changed. Scenario 01 shows accept and three refusals |
| The derived preview (hostname, issuer, JWKS, OAuth2 client, edge route, DNS records, status rows) | **REAL-BUT-ELSEWHERE** | The goatnet renders all of it from the declaration. This repo prints the same shapes; it renders nothing |
| `hostnames:` — several endpoint names, one level of nesting | **REAL-BUT-ELSEWHERE** | The goatnet iterates the list for the route, the DNS records and the status rows, and covers the names with `*.<site>.<zone>` plus one `*.<name>.<site>.<zone>` per service that nests. The same ownership rule is enforced here and there. There is no wildcard DNS: mesh DNS is served from a flat file of literal records. Scenario 04 previews what a fourteen-name declaration produces and what the certificate carries |
| `tls: partner` — you terminate on your own host | **REAL-BUT-ELSEWHERE** | The goatnet publishes no route, no backend and no certificate for these names, and points the DNS records at `mesh_ip`. Nothing in this repo serves TLS; scenario 04 shows the derived difference |
| The footprint check (`tools/footprint-guard-demo.sh`) | **REAL** logic, copied | The goatnet's check reproduced — same declaration glob shape, file-name rule, default tokens, messages and temporary/permanent split — run over a scratch git tree. The directory names in that tree are the demo's, not the goatnet's. Scenario 03 shows FAIL then OK |
| The OIDC issuer (`local-issuer/issuer.py`) | **SIMULATED** | Stands in for the goatnet's Ory Hydra. It publishes a real discovery document and JWKS and signs real RS256 tokens, so your service's verification is real. It has no login flow and mints whatever claims it is asked for, which Hydra never does |
| Registering, pinning and deleting the OAuth2 client | **REAL-BUT-ELSEWHERE** | The goatnet does all three from the declaration. Not run here |
| The pre-flight (health over the mesh, `EXTERNAL-INFRA` membership, the zone carries the name) | **REAL-BUT-ELSEWHERE** | The goatnet checks all three before applying. Not run here |
| The edge, the DNS push, the status-page re-render | **REAL-BUT-ELSEWHERE** | All three happen on the goatnet when a declaration is applied. Not run here |
| Machine enrollment of your host | **REAL-BUT-ELSEWHERE** | Your custodian enrolls it. Described in [do-it-for-real.md](do-it-for-real.md), not run here |
| The `aff.id` claim on a goatnet | **REAL-BUT-ELSEWHERE, off by default** | goat defines the affiliation claim; minting it is a per-goatnet switch that is off by default. The simulated issuer mints it so the rule can be shown |
| `email_verified` on console-minted identities | **depends on the goatnet** | A goatnet whose identity console mints identities without `email_verified: true` is refused by this rule until those identities are verified at the identity provider. The rule is correct as written |
| The report (`report/report.html`) | **REAL** capture | Generated from the scenario outputs by `report/generate-report.sh`; re-run it and every line is read back fresh |

## The discipline

If a later change makes a simulated or elsewhere thing look like it runs here, that is a
regression. When in doubt, grade down and say so in the scenario's `honesty:` lines.
