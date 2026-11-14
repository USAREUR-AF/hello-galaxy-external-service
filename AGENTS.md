# AGENTS.md

Instructions for AI coding agents, and a short version for anyone working here. [CONTRIBUTING.md](CONTRIBUTING.md) is the full process.

## What this repository is

hello-galaxy-external-service demonstrates goat's external service path: a service that the goatnet does not run uses the goatnet's sign-in from one declaration file, verifies tokens itself, authorizes from its own roster, and is withdrawn the same way. Everything runs on one machine.

It is one of the Hello Galaxy demonstrations: small, runnable examples, each showing one part of [goat](https://github.com/USAREUR-AF/goatcore). It holds no goat source code.

## Layout

| Path | What |
|---|---|
| `scenarios/` | one directory per scenario: `README.md` and `run.sh` |
| `examples/` | example declaration files for the made-up goatnet `zagros` |
| `tools/validate-declaration.py` | checks a declaration and renders its preview |
| `local-issuer/`, `service/` | the local token issuer and the example service |
| `report/` | the HTML report and its generator |
| `docs/` | background, including `honesty-matrix.md` |

## Before you push

CI (`.github/workflows/ci.yml`) runs these:

```bash
shellcheck -e SC1090,SC1091,SC2034 lib/hello-external.sh scenarios/*/run.sh tools/*.sh report/generate-report.sh
python3 -m pip install -r requirements.txt
python3 tools/validate-declaration.py examples/hello-external.zagros.yml --site-id zagros
for s in 01-declare 02-sign-in-and-authorize 03-withdraw 04-partner-platform; do
  NO_COLOR=1 bash scenarios/$s/run.sh
done
NO_COLOR=1 bash report/generate-report.sh
```

Every directory under `scenarios/` holds a `README.md` and an executable `run.sh`; CI checks both. Every Python file must compile (`python3 -m py_compile`).

## Rules

1. **Nothing from a real deployment.** No hostname, domain, address, key or person of a real goatnet goes into a file or a commit message. Use made-up names, documentation addresses (RFC 5737) and `example.org` mail.
2. **Commits.** Conventional Commits subject of 100 characters or fewer, with a scope (`fix(<component>): …`). Every commit is signed off (`git commit -s`, the DCO) and signed with a key GitHub verifies. The organization's required check `verified-commits` refuses a pull request that holds an unverified commit.
3. **One logical change per pull request.**
4. **Vulnerabilities** go through [SECURITY.md](SECURITY.md), never a public issue.

The contribution guide for goat as a whole is [goatcore CONTRIBUTING.md](https://github.com/USAREUR-AF/goatcore/blob/main/CONTRIBUTING.md).
