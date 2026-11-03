# Do it for real

Bringing a real service up on a goatnet. The scenarios in this repo show the same
path on a laptop with a simulated issuer; this page is the live version, and every step on
it needs a running goatnet and its platform team. Any appropriate goatnet you have access to
works:
EFDI, the shared sandbox goatnet that partners are onboarded to (if you are onboarded to it); <!-- oss-allow: operator-approved public example goatnet -->
a goatlite you stand up yourself (goatcore's
[goatlite quickstart](https://github.com/usareur-af/goatcore/blob/main/docs/tutorials/00-goatlite.md)
or the example environment [`hello-galaxy-goatenv`](https://github.com/usareur-af/hello-galaxy-goatenv)),
in which case you are also its platform team; or another goatnet you have access to.
The platform side is goatcore's
[external service golden path](https://github.com/usareur-af/goatcore/blob/main/docs/design/external-service-golden-path.md)
and its play `ops/ansible/external-service.yml`.

Two people are involved and the split matters:

- **You**, the service owner. You run a host, write one declaration, hold your own
  client secret and configure your own fence. Everything below marked **you** is yours.
- **The platform team.** They apply the declaration to the goatnet and hand you back the
  lines you configure from. They need the goatnet's own tooling to do that; you do not,
  and none of it is in this repo.

## 1. Your host joins the mesh as a machine — *you, with a custodian*

Your service runs on your own host. A custodian enrolls it through machine enrollment.
The node class for somebody else's hardware serving our users lands the host in the
`<SITE>-EXTERNAL-INFRA` group: every role group reaches it one-way on any port, and it
initiates only toward `INFRA`. You are given a single-use setup key and run `netbird up`
with it.

Check before going on: the host has a `100.64/10` address and holds
`<SITE>-EXTERNAL-INFRA`. The goatnet's pre-flight asserts this and names what it found
when it fails. The fix is always the host's membership, never the people's.

## 2. Write the declaration — *you*

Copy [`examples/hello-external.zagros.yml`](../examples/hello-external.zagros.yml), rename it
for the goatnet you are using and edit it. Set `backend_url` to your host's mesh IP and the port your fence binds. Keep
`retire_after` if the service is temporary.

```bash
python3 tools/validate-declaration.py my-service.yml
```

That applies the same rules the goatnet applies, so a refusal shows up here rather than
in someone else's review. See [the-declaration.md](the-declaration.md) for the schema.

Hand the file to the platform team. It is the entire goatnet-side change.

## 3. Put the client secret in your own deploy environment — *you*

```bash
export HELLO_OAUTH2_CLIENT_SECRET="$(openssl rand -hex 32)"
```

Tell the platform team the variable's **name**, which is what `client.secret_env`
declares. The same value has to be in their environment when they apply, and in yours
when you configure the fence. Two different values is a login loop that looks like an
identity-provider fault and is not.

## 4. The goatnet applies it — *the platform team*

One command, and in order it: checks the declaration; checks the goatnet's DNS zone
carries the name; probes your `backend_url` + `health_path` over the mesh from the
goatnet's edge; asserts your host is one mesh peer in `<SITE>-EXTERNAL-INFRA`; registers
the OAuth2 client and pins its lifespans; then publishes the edge route, the DNS record
and the status row.

Nothing in that list is something you run. If it fails, the message names which check and
what it found.

## 5. What comes back, and what you do with it — *you*

The apply prints the lines you configure from:

```
hostname:     https://hello.<site>.<zone>
issuer:       https://oauth2.<site>.<zone>/   (trailing slash is load-bearing)
jwks:         https://oauth2.<site>.<zone>/.well-known/jwks.json
issuer pin:   oauth2.<site>.<zone> -> <edge mesh ip>   (hosts on the mesh without mesh DNS)
client_id:    oauth2-proxy-hello-external
redirect_uri: https://hello.<site>.<zone>/oauth2/callback
secret:       $HELLO_OAUTH2_CLIENT_SECRET  (same variable on both sides)
door:         authenticated   (what your own fence decides; recorded, not enforced there)
```

Configure your service from those lines:

| Service setting | Value |
|---|---|
| `HELLO_ISSUER` | the issuer line, with the trailing slash |
| `HELLO_JWKS_URL` | the jwks line |
| `HELLO_CLIENT_ID` | the client_id line |
| `HELLO_BIND` | your host's mesh IP, never `0.0.0.0` |
| oauth2-proxy `OAUTH2_PROXY_CLIENT_ID` / `_CLIENT_SECRET` | the client_id line; `$HELLO_OAUTH2_CLIENT_SECRET` |
| oauth2-proxy `OAUTH2_PROXY_REDIRECT_URL` | the redirect_uri line |
| oauth2-proxy cookie lifetime | equal to `client.token_lifespan` (8h), because the fence holds no refresh token |
| `/etc/hosts` in the containers | the issuer pin line, when your host does not use mesh DNS |

Run oauth2-proxy beside your service on the same host, configured to forward the id_token
as a bearer. Publish no host port except through the fence.

## 6. Verify — *you*

- `https://hello.<site>.<zone>/healthz` answers 200 from a mesh peer
- `https://hello.<site>.<zone>/api/me` redirects to the goatnet's sign-in and, after it,
  returns the principal for a rostered person and 403 for an unrostered one
- the status page shows the row "Hello external service"

## 7. Withdraw — *you, then the platform team*

Set `enabled: false` in the declaration and say so. Withdrawal is your edit, not their
flag: a removal is refused while the declaration is still enabled, and that ordering is
what stops a live service being switched off by accident.

They then apply it once more. The OAuth2 client is deleted and the edge route, the
certificate name, the DNS record and the status row all disappear, because the loops
that produced them no longer see the service. Delete the declaration file afterwards if
you like — after the apply, not before, or the OAuth2 client is left behind.

Nothing on the goatnet then remembers the service. Your own host, roster and audit log
are yours to keep or delete.
