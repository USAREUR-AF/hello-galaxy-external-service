# 03 — Withdraw

The same file, marked withdrawn, takes everything away. A CI check on the goatnet's
configuration keeps the service's name out of every other file, which is what makes the
teardown complete rather than hopeful.

```bash
bash scenarios/03-withdraw/run.sh
```

## What it does

1. Shows withdrawal refused while the declaration is still `enabled: true`. Withdrawing
   a live service is your edit, not the platform team's flag.
2. Sets `enabled: false` on a copy and shows withdrawal accepted and the service no
   longer applicable.
3. Lists what the goatnet removes: the OAuth2 client, the edge route and its certificate
   name, the DNS record, the status row.
4. Runs `tools/footprint-guard-demo.sh`: plants a stray reference to `hello-external`
   in an unrelated file inside a scratch tree, runs the footprint check's logic, shows
   the FAIL with `file:line`, removes the line, shows OK. A permanent declaration in the
   same tree is only NOTED, exactly as on the goatnet.

## What it does not do

Removing the real route, record and row happens on the goatnet and is not run here.
Withdraw in this order: set `enabled: false`, have it applied, then delete the file if you
want to. Deleting the file first leaves the OAuth2 client registered.
