# 01 — Declare

One YAML file is the service's whole goatnet-side footprint. This scenario validates it
exactly as the goatnet does, and prints what the goatnet derives from it.

```bash
bash scenarios/01-declare/run.sh
```

## What it does

1. Prints `examples/hello-external.zagros.yml`.
2. Runs `tools/validate-declaration.py` on it: accepted, then the preview of the
   hostname, issuer, JWKS URL, OAuth2 client, edge route and certificate names, DNS
   record, status row and footprint-check tokens.
3. Flips a copy to a LAN backend (`192.168.1.50`) and shows the refusal.
4. Flips a copy to `door: open` and shows the refusal.
5. Flips a copy to a past `retire_after` and shows the refusal.

## What it proves

The rules here are the goatnet's, line for line (see
[docs/the-declaration.md](../../docs/the-declaration.md), "What is checked, exactly").
A declaration that passes here passes on the goatnet.

## What it does not do

It renders nothing. The preview reproduces the shapes of what the goatnet publishes so
you can see them without a goatnet (honesty matrix, "REAL-BUT-ELSEWHERE").
