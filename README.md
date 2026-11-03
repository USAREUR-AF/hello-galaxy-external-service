# hello-galaxy-external-service

**A hands-on demonstration of goat's external service golden path. A service the
goatnet does not run borrows the goatnet's sign-in from one declaration file, verifies
the tokens itself, authorizes from its own roster, and is withdrawn the same way with
nothing left behind. Runs on a laptop in a few minutes.**

This repo is a series of small, self-contained scenarios. Each one is a short runbook
plus one script that narrates what happens as it happens. You do not need to know goat
to follow along, and you do not need access to the goatnet's configuration: everything
here runs on your own machine.

The rule of the series: show, don't tell. Where a thing runs here, the scenario proves
it. Where a thing runs on the goatnet and not here, or where a stand-in is used, the
scenario says so. The full accounting is [the honesty matrix](docs/honesty-matrix.md).

**Who this is for.** You are bringing up a service on your own host and you want it to
use the goatnet's sign-in. Your whole side of the work is one YAML file and the fence
in front of your service. The platform team does the rest, and this repo shows you
exactly what they will do and what you get back.

## What you'll learn

| Question | Plain answer | Where the demo shows it |
|---|---|---|
| What is an external service? | Off-box, non-core, often temporary. It wants goatnet sign-in, a name on the goatnet's edge and a status row | [docs/00](docs/00-what-is-an-external-service.md), scenario 00 |
| What do I write? | One YAML file. It is refused for a LAN backend, an unknown door or a passed retire date | [docs/the-declaration.md](docs/the-declaration.md), scenario 01 |
| Where does it show on the goatnet's status page? | On its **External services** page, under your `owner`, not among the goatnet's own services. You choose which hostnames are listed (`status.list`, `status.hostnames.<entry>.list`), how each is probed, and mark a surface `planned` while it is not up yet | [docs/the-declaration.md](docs/the-declaration.md#on-the-status-page), scenario 04 |
| Who decides who gets in? | The goatnet authenticates; your service authorizes from its roster. Claims are evidence, not grants | scenario 02 |
| Why the trailing slash on the issuer? | `iss` is an exact string match; without the slash every token is refused | scenario 02, step (g) |
| How does it leave? | `enabled: false`, and the goatnet unwinds everything it derived. A check refuses any stray reference to the name | scenario 03 |
| I have thirteen endpoints, not one | One declaration carries them all via `hostnames:`, each prefixed or nested one level under your own name (`northwind-api`, `api.northwind`). `tls:` decides whether the goatnet's edge is in front or you terminate on your own host | scenario 04 |

## Quick start

Prerequisites: Python 3.9 or later, `curl`, `git`.

```bash
pip install -r requirements.txt          # PyJWT, cryptography, PyYAML

bash scenarios/00-orient/run.sh
bash scenarios/01-declare/run.sh                 # validate the declaration, see what it derives
bash scenarios/02-sign-in-and-authorize/run.sh   # every relying-party rule, with real tokens
bash scenarios/03-withdraw/run.sh                # withdraw, and the footprint check
bash scenarios/04-partner-platform/run.sh        # a platform with several endpoints; who terminates TLS

report/generate-report.sh                        # runs all five, writes report/report.html
```

Scenario 02 starts two local processes on `127.0.0.1` (ports 9401 and 9402, overridable
with `HX_ISSUER_PORT` and `HX_SERVICE_PORT`) and stops them on exit. Everything written
at runtime goes under `.run/`, which is ignored by git.

The scripts pick the first of `python3`, `python` that has the three dependencies. Set
`HX_PY` to force a particular interpreter.

Nothing here talks to a goatnet. The live steps are in
[docs/do-it-for-real.md](docs/do-it-for-real.md).

## Using it for a real service

Everything above runs on your laptop against examples. When your service is ready for
a goatnet, the same file is what you hand its platform team:

1. Copy a file from [`examples/`](examples/), rename it `<name>.<goatnet>.yml`, edit it,
   and run `tools/validate-declaration.py` on it.
2. The platform team applies it with goatcore's `ops/ansible/external-service.yml`
   ([the external service golden path](https://github.com/usareur-af/goatcore/blob/main/docs/design/external-service-golden-path.md)).
   That step needs the goatnet's own credentials, so it stays with them.
3. You configure your service from the lines the apply prints back.
   [docs/do-it-for-real.md](docs/do-it-for-real.md) walks the whole path.

To change your service later, edit the same file and have it applied again. To withdraw
it, set `enabled: false` and have it applied; delete the file only after that, because a
file deleted first leaves your sign-in client registered.

## The scenarios

| Scenario | What it shows |
|---|---|
| [00-orient](scenarios/00-orient) | the concept, the trust rule, the boundary rule; prerequisite check |
| [01-declare](scenarios/01-declare) | the declaration validated exactly as the goatnet validates it; the derived hostname, issuer, JWKS, OAuth2 client, edge route, DNS record and status row; three refusals |
| [02-sign-in-and-authorize](scenarios/02-sign-in-and-authorize) | rostered 200, unverified email 403, vendor auto-roster 200, unknown org 403, stale snapshot 403, wrong audience 401, issuer without slash 401, org mismatch 200 with audit, expired 401 |
| [03-withdraw](scenarios/03-withdraw) | withdrawal refused while the service is enabled; `enabled: false`; what the goatnet removes; the footprint check failing on a stray reference and passing once it is gone |
| [04-partner-platform](scenarios/04-partner-platform) | one declaration carrying fourteen endpoint names under one name; what the certificate carries; who terminates TLS, and what changes when it is you; four refusals |

## Repo layout

```
lib/hello-external.sh        shared scenario library (narration, assertions, process control)
local-issuer/issuer.py       SIMULATED OIDC issuer: RS256 keypair, discovery, JWKS, POST /mint
service/hello_service.py     the hello service: the real relying-party rules
service/roster.json          the service's own authorization records
service/org-snapshot.json    a snapshot of the goatnet's organisation catalog
examples/                    worked declarations the scenarios run against
tools/validate-declaration.py   the goatnet's well-formedness rules + the derived preview
tools/footprint-guard-demo.sh   the footprint check's logic on a scratch tree: FAIL then OK
scenarios/                   00-orient, 01-declare, 02-sign-in-and-authorize, 03-withdraw, 04-partner-platform
report/                      generate-report.sh -> report.html
docs/                        00-what-is-an-external-service, the-declaration, honesty-matrix, do-it-for-real
```

## What runs here, and what runs on the goatnet

| Here | On the goatnet | Record |
|---|---|---|
| `examples/<name>.<goatnet>.yml` | the same file, in the goatnet's configuration, applied by its platform team | ADR 1178 |
| `tools/validate-declaration.py` | the same rules, checked before anything is applied | ADR 1178 |
| the derived preview | the edge route and certificate, the mesh DNS record, the status-page row | ADR 1178 |
| `tools/footprint-guard-demo.sh` | a check that fails any change naming a temporary service outside its declaration | ADR 1178 |
| `local-issuer/issuer.py` (simulated) | the goatnet's Ory Hydra at `https://oauth2.<site>.<zone>/` | goat's identity plane |
| `service/hello_service.py` | what you run beside oauth2-proxy on your own host | ADR 1073 (`door`); goat's affiliation claim (`aff`) |
| the `EXTERNAL-INFRA` tier | your host, enrolled as a machine by its custodian | the golden path design, "the host" |

The design record behind all of it is goatcore's
[ADR 1178, "the external service golden path"](https://github.com/usareur-af/goatcore/blob/main/docs/adr/1178-external-service-golden-path.md)
and its design document
[`docs/design/external-service-golden-path.md`](https://github.com/usareur-af/goatcore/blob/main/docs/design/external-service-golden-path.md).

Part of the hello-galaxy family of runnable goat demos.

## Licence

Apache License 2.0 ([LICENSE](LICENSE)). See [NOTICE](NOTICE),
[CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
